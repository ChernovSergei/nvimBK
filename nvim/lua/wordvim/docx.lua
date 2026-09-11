-- ============================================================
-- lua/wordvim/docx.lua
--
-- DOCX open/save layer.
--
-- Important design choices:
-- 1. Neovim buffer shows clean Markdown/text.
-- 2. Paragraph styles are hidden in wordvim.styles.
-- 3. styles.xml is read from a TEMPORARY DOCX COPY to avoid
--    Windows file-lock conflicts while Neovim opens the file.
-- ============================================================

local M = {}

local styles = require("wordvim.styles")
local paragraphs = require("wordvim.paragraphs")
local indents = require("wordvim.indents")
local lists = require("wordvim.lists")
local pagebreaks = require("wordvim.pagebreaks")
local pagesettings = require("wordvim.pagesettings")
local toc = require("wordvim.toc")
local crossrefs = require("wordvim.crossrefs")
local formatting = require("wordvim.formatting")
local images = require("wordvim.images")
local styleui = require("wordvim.styleui")

local group = vim.api.nvim_create_augroup("WordVimDocx", { clear = true })
local window_restore = {}

local markdown_format =
  "markdown"
  .. "+bracketed_spans"
  .. "+fenced_divs"
  .. "+strikeout"
  .. "+pipe_tables"
  .. "+raw_html"

-- A temporary text token used only while converting DOCX <-> Markdown.
-- It makes a real, empty Word paragraph visible to Pandoc so Word Vim can
-- distinguish it from Markdown separator blank lines.  The token is never
-- left in the user's DOCX: it is removed from document.xml before save.
local EMPTY_PARAGRAPH_MARKER = "WORDVIM_EMPTY_PARAGRAPH_7D4E91C2"

local function ps_escape(value)
  return tostring(value or ""):gsub("'", "''")
end

local function run_powershell(script)
  local output = vim.fn.system({
    "powershell",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    script,
  })

  return vim.v.shell_error == 0, output
end

local function copy_file(src, dst)
  local ok, result, err = pcall(vim.uv.fs_copyfile, src, dst)
  if not ok or not result then
    return false, tostring(err or result)
  end
  return true
end

-- ============================================================
-- Empty Word paragraphs
-- ============================================================

-- Pandoc normally drops empty <w:p/> elements when DOCX is converted to
-- Markdown because Markdown blank lines are paragraph separators, not empty
-- paragraphs.  Convert a COPY of the DOCX and temporarily put a unique token
-- inside truly empty Word paragraphs.  Pandoc then preserves their positions.
--
-- The original DOCX is never modified here.
local function make_pandoc_read_copy_with_empty_markers(docx)
  local temp_docx = vim.fn.tempname() .. ".docx"

  local copied, copy_err = copy_file(docx, temp_docx)
  if not copied then
    return nil, tostring(copy_err)
  end

  local path = ps_escape(temp_docx)
  local marker = ps_escape(EMPTY_PARAGRAPH_MARKER)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$path = '%s'
$marker = '%s'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Update')
    $entry = $zip.GetEntry('word/document.xml')
    if ($null -eq $entry) { throw 'word/document.xml not found' }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    $xmlText = $reader.ReadToEnd()
    $reader.Close()

    [xml]$xml = $xmlText
    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $paragraphs = $xml.SelectNodes('//w:body//w:p', $ns)

    foreach ($p in $paragraphs) {
        # A paragraph is considered truly empty only when it contains no
        # visible text and no structural inline object/field/break/tab.
        # Paragraph properties (w:pPr) are intentionally allowed.
        $meaningful = $p.SelectSingleNode(
          './/w:t | .//w:tab | .//w:br | .//w:cr | .//w:drawing | .//w:object | .//w:pict | .//w:fldChar | .//w:instrText | .//w:sym | .//w:footnoteReference | .//w:endnoteReference',
          $ns
        )

        if ($null -eq $meaningful) {
            $r = $xml.CreateElement('w', 'r', $nsUri)
            $t = $xml.CreateElement('w', 't', $nsUri)
            $t.InnerText = $marker
            [void]$r.AppendChild($t)
            [void]$p.AppendChild($r)
        }
    }

    $entry.Delete()
    $newEntry = $zip.CreateEntry('word/document.xml')
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $xml.Save($writer)
    $writer.Close()
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
]], path, marker)

  local ok, output = run_powershell(script)
  if not ok then
    vim.fn.delete(temp_docx)
    return nil, output
  end

  return temp_docx
end

-- Remove the temporary marker text from the generated DOCX while keeping the
-- paragraph itself (and its pPr/style/spacing).  Thus the saved file contains
-- a genuine empty Word paragraph, not marker text.
local function remove_empty_paragraph_markers(docx)
  local path = ps_escape(docx)
  local marker = ps_escape(EMPTY_PARAGRAPH_MARKER)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$path = '%s'
$marker = '%s'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Update')
    $entry = $zip.GetEntry('word/document.xml')
    if ($null -eq $entry) { throw 'word/document.xml not found' }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    $xmlText = $reader.ReadToEnd()
    $reader.Close()

    [xml]$xml = $xmlText
    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $nodes = @($xml.SelectNodes('//w:t[text()="' + $marker + '"]', $ns))
    foreach ($t in $nodes) {
        $run = $t.ParentNode
        if ($null -ne $run -and $run.LocalName -eq 'r') {
            [void]$run.ParentNode.RemoveChild($run)
        }
        else {
            $t.InnerText = ''
        }
    }

    $entry.Delete()
    $newEntry = $zip.CreateEntry('word/document.xml')
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $xml.Save($writer)
    $writer.Close()
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
]], path, marker)

  local ok, output = run_powershell(script)
  if not ok then
    vim.notify(
      "Word Vim: could not restore empty Word paragraphs:\n" .. output,
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

local function create_backup(original)
  local backup = original .. ".bak"

  if vim.fn.filereadable(backup) == 1 then
    return true
  end

  local ok, err = copy_file(original, backup)
  if not ok then
    vim.notify(
      "Word Vim: could not create backup:\n" .. tostring(err),
      vim.log.levels.ERROR
    )
    return false
  end

  vim.notify("Word Vim backup created:\n" .. backup, vim.log.levels.INFO)
  return true
end

local function apply_docx_window_profile(buf, win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  if not window_restore[win] then
    window_restore[win] = {
      wrap = vim.wo[win].wrap,
      linebreak = vim.wo[win].linebreak,
      number = vim.wo[win].number,
      relativenumber = vim.wo[win].relativenumber,
      signcolumn = vim.wo[win].signcolumn,
      statusline = vim.wo[win].statusline,
    }
  end

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = true
  vim.wo[win].relativenumber = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].statusline =
    "%t %m %= %{v:lua.WordVimPageStatus()} %l:%c %p%%"
end

local function restore_window_profile(win)
  local saved = window_restore[win]
  if not saved or not vim.api.nvim_win_is_valid(win) then
    window_restore[win] = nil
    return
  end

  vim.wo[win].wrap = saved.wrap
  vim.wo[win].linebreak = saved.linebreak
  vim.wo[win].number = saved.number
  vim.wo[win].relativenumber = saved.relativenumber
  vim.wo[win].signcolumn = saved.signcolumn
  vim.wo[win].statusline = saved.statusline
  window_restore[win] = nil
end

local function apply_docx_buffer_profile(buf)
  vim.b[buf].wordvim_docx = true
  vim.bo[buf].smartindent = false
  vim.bo[buf].undofile = false
  vim.bo[buf].formatoptions = ""

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    apply_docx_window_profile(buf, win)
  end
end

-- ============================================================
-- Read styles.xml from a temporary DOCX copy
-- ============================================================

local function read_word_styles_from_copy(docx)
  local temp_docx = vim.fn.tempname() .. ".docx"

  local copied, copy_err = copy_file(docx, temp_docx)
  if not copied then
    vim.notify(
      "Word Vim: could not create temporary DOCX copy:\n" .. tostring(copy_err),
      vim.log.levels.WARN
    )
    return {}
  end

  local path = ps_escape(temp_docx)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)

    $entry = $zip.GetEntry('word/styles.xml')
    if ($null -eq $entry) {
        throw 'word/styles.xml not found'
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
    $reader.Close()

    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $all = $xml.SelectNodes('//w:styles/w:style', $ns)

    foreach ($style in $all) {
        $type = $style.GetAttribute('type', $nsUri)
        $id = $style.GetAttribute('styleId', $nsUri)

        $nameNode = $style.SelectSingleNode('w:name', $ns)
        if ($null -eq $nameNode) {
            continue
        }

        $name = $nameNode.GetAttribute('val', $nsUri)

        $basedOn = ''
        $based = $style.SelectSingleNode('w:basedOn', $ns)

        if ($null -ne $based) {
            $basedId = $based.GetAttribute('val', $nsUri)

            foreach ($candidate in $all) {
                if ($candidate.GetAttribute('styleId', $nsUri) -eq $basedId) {
                    $candidateName = $candidate.SelectSingleNode('w:name', $ns)

                    if ($null -ne $candidateName) {
                        $basedOn = $candidateName.GetAttribute('val', $nsUri)
                    }

                    break
                }
            }
        }

        $font = ''
        $fonts = $style.SelectSingleNode('w:rPr/w:rFonts', $ns)
        if ($null -ne $fonts) {
            $font = $fonts.GetAttribute('ascii', $nsUri)
        }

        $size = ''
        $sz = $style.SelectSingleNode('w:rPr/w:sz', $ns)
        if ($null -ne $sz) {
            $half = $sz.GetAttribute('val', $nsUri)
            if (-not [string]::IsNullOrWhiteSpace($half)) {
                $size = ([double]$half / 2)
            }
        }

        $bold = 'no'
        if ($null -ne $style.SelectSingleNode('w:rPr/w:b', $ns)) {
            $bold = 'yes'
        }

        $italic = 'no'
        if ($null -ne $style.SelectSingleNode('w:rPr/w:i', $ns)) {
            $italic = 'yes'
        }

        $underline = 'no'
        if ($null -ne $style.SelectSingleNode('w:rPr/w:u', $ns)) {
            $underline = 'yes'
        }

        $color = ''
        $colorNode = $style.SelectSingleNode('w:rPr/w:color', $ns)
        if ($null -ne $colorNode) {
            $color = $colorNode.GetAttribute('val', $nsUri)
        }

        $alignment = ''
        $jc = $style.SelectSingleNode('w:pPr/w:jc', $ns)
        if ($null -ne $jc) {
            $alignment = $jc.GetAttribute('val', $nsUri)
        }

        $before = ''
        $after = ''
        $spacing = $style.SelectSingleNode('w:pPr/w:spacing', $ns)

        if ($null -ne $spacing) {
            $b = $spacing.GetAttribute('before', $nsUri)
            $a = $spacing.GetAttribute('after', $nsUri)

            if (-not [string]::IsNullOrWhiteSpace($b)) {
                $before = ([double]$b / 20)
            }

            if (-not [string]::IsNullOrWhiteSpace($a)) {
                $after = ([double]$a / 20)
            }
        }

        Write-Output(
          $type      + "`t" +
          $id        + "`t" +
          $name      + "`t" +
          $basedOn   + "`t" +
          $font      + "`t" +
          $size      + "`t" +
          $bold      + "`t" +
          $italic    + "`t" +
          $underline + "`t" +
          $color     + "`t" +
          $alignment + "`t" +
          $before    + "`t" +
          $after
        )
    }
}
finally {
    if ($null -ne $zip) {
        $zip.Dispose()
    }
}
]], path)

  local ok, output = run_powershell(script)
  vim.fn.delete(temp_docx)

  if not ok then
    vim.notify(
      "Word Vim: could not read Word styles:\n" .. output,
      vim.log.levels.WARN
    )
    return {}
  end

  local result = {}

  for line in output:gmatch("[^\r\n]+") do
    local fields = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do
      table.insert(fields, field)
    end

    if fields[1] and fields[2] and fields[3] then
      table.insert(result, {
        type = fields[1],
        id = fields[2],
        name = fields[3],
        based_on = fields[4] or "",
        font = fields[5] or "",
        size = fields[6] or "",
        bold = fields[7] or "no",
        italic = fields[8] or "no",
        underline = fields[9] or "no",
        color = fields[10] or "",
        alignment = fields[11] or "",
        before = fields[12] or "",
        after = fields[13] or "",
      })
    end
  end

  return result
end

-- ============================================================
-- Remove visible paragraph custom-style wrappers
-- ============================================================

local function clean_style_blocks(lines)
  local clean = {}
  local assignments = {}
  local i = 1

  local function is_div_close(line)
    return line:match("^%s*:::%s*$") ~= nil
  end

  local function list_normal_prefix(line)
    -- Pandoc can wrap a Word paragraph style INSIDE a Markdown
    -- list item, for example:
    --
    -- -   ::: {custom-style="Normal"}
    --     text
    --     :::
    --
    -- The old cleaner only recognized ::: at column 1, so these
    -- wrappers remained visible in Neovim.
    --
    -- "Normal" is Word's default paragraph style and does not
    -- need a hidden Word Vim style mark. We can safely unwrap it.

    local prefix = line:match(
      '^(%s*[-+*]%s+):::%s*{custom%-style="Normal"}%s*$'
    )

    if prefix then
      return prefix
    end

    prefix = line:match(
      '^(%s*%d+[%.%)]%s+):::%s*{custom%-style="Normal"}%s*$'
    )

    return prefix
  end

  while i <= #lines do
    -- --------------------------------------------------------
    -- Case 1: custom-style="Normal" nested inside a list item
    -- --------------------------------------------------------
    local list_prefix = list_normal_prefix(lines[i])

    if list_prefix then
      i = i + 1

      local first = true

      while i <= #lines and not is_div_close(lines[i]) do
        local content = lines[i]

        if first then
          -- Remove Pandoc's indentation belonging to the fenced
          -- Div and put the actual text back onto the list item.
          content = content:gsub("^%s*", "")
          table.insert(clean, list_prefix .. content)
          first = false
        else
          -- Preserve continuation lines. Pandoc already gave
          -- them list-compatible indentation.
          table.insert(clean, content)
        end

        i = i + 1
      end

      if i <= #lines and is_div_close(lines[i]) then
        i = i + 1
      end

    else
      -- ------------------------------------------------------
      -- Case 2: ordinary top-level paragraph style fenced Div
      -- ------------------------------------------------------
      local style_name = lines[i]:match(
        '^%s*:::%s*{custom%-style="([^"]+)"}%s*$'
      )

      if style_name then
        i = i + 1
        local first_content_row = nil

        while i <= #lines and not is_div_close(lines[i]) do
          table.insert(clean, lines[i])

          if not first_content_row and lines[i]:match("%S") then
            first_content_row = #clean - 1
          end

          i = i + 1
        end

        -- "Normal" is the default Word paragraph style, so there
        -- is no reason to track it with an extmark. All other
        -- paragraph styles remain hidden and are reconstructed
        -- on save.
        if
          first_content_row
          and style_name:lower() ~= "normal"
        then
          table.insert(assignments, {
            row = first_content_row,
            style = style_name,
          })
        end

        if i <= #lines and is_div_close(lines[i]) then
          i = i + 1
        end
      else
        table.insert(clean, lines[i])
        i = i + 1
      end
    end
  end

  return clean, assignments
end

local function compact_editor_lines(lines, assignments)
  local compact = {}
  local old_to_new = {}

  local in_fence = false
  local fence_token = nil

  for old_index, line in ipairs(lines) do
    local old_row = old_index - 1
    local trimmed = vim.trim(line)

    local fence = trimmed:match("^(```+)")
      or trimmed:match("^(~~~+)")

    if fence then
      if not in_fence then
        in_fence = true
        fence_token = fence:sub(1, 1)
      elseif fence:sub(1, 1) == fence_token then
        in_fence = false
        fence_token = nil
      end

      old_to_new[old_row] = #compact
      table.insert(compact, line)

    elseif in_fence then
      old_to_new[old_row] = #compact
      table.insert(compact, line)

    elseif vim.trim(line) == EMPTY_PARAGRAPH_MARKER then
      -- This is a real empty <w:p/> that was temporarily marked in the
      -- DOCX copy before Pandoc read it. Keep one visible empty editor row.
      old_to_new[old_row] = #compact
      table.insert(compact, "")

    elseif line:match("^%s*$") then
      -- Ordinary Markdown blank lines are only paragraph separators.
      -- Unlike the marker above, they do NOT represent empty Word paragraphs.

    else
      old_to_new[old_row] = #compact
      table.insert(compact, line)
    end
  end

  local remapped = {}

  for _, item in ipairs(assignments or {}) do
    local new_row = old_to_new[item.row]

    if new_row ~= nil then
      table.insert(remapped, {
        row = new_row,
        style = item.style,
      })
    end
  end

  return compact, remapped
end

local function build_markdown_for_save(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Replace caption/reference display text with safe temporary markers.
  lines = crossrefs.prepare_markdown_lines(buf, lines)

  -- Convert Word Vim list labels/symbols back to valid nested Markdown
  -- before the existing DOCX-save logic processes them.
  lines = lists.to_markdown_lines(lines)

  local style_map = styles.get_style_map(buf)
  local result = {}

  local function is_table_line(line)
    local t = vim.trim(line or "")
    return t:match("^|.*|$") ~= nil
  end

  local function is_list_line(line)
    return (line or ""):match("^%s*[-+*]%s+") ~= nil
      or (line or ""):match("^%s*%d+[%.%)]%s+") ~= nil
  end

  local function is_fence(line)
    local t = vim.trim(line or "")
    return t:match("^```+") ~= nil
      or t:match("^~~~+") ~= nil
  end

  local function hard_break(line)
    return (line or ""):match("%s%s$") ~= nil
  end

  local function ensure_blank()
    if #result > 0 and result[#result] ~= "" then
      table.insert(result, "")
    end
  end

  local function emit_page_break(row)
    if pagebreaks.has_before(buf, row) then
      ensure_blank()
      table.insert(
        result,
        pagebreaks.marker_for_row(row)
      )
      ensure_blank()
    end
  end

  local i = 1
  local in_fence = false

  while i <= #lines do
    local line = lines[i]
    local row = i - 1

    if toc.has_anchor(buf, row) then
      emit_page_break(row)
      ensure_blank()
      table.insert(
        result,
        toc.marker_for_row(row)
      )
      ensure_blank()
      i = i + 1

    elseif is_fence(line) then
      emit_page_break(row)
      ensure_blank()
      in_fence = not in_fence
      table.insert(result, line)
      i = i + 1

      while i <= #lines and in_fence do
        local code_line = lines[i]
        table.insert(result, code_line)

        if is_fence(code_line) then
          in_fence = false
        end

        i = i + 1
      end

      ensure_blank()

    elseif is_table_line(line) then
      emit_page_break(row)
      ensure_blank()

      while i <= #lines and is_table_line(lines[i]) do
        table.insert(result, lines[i])
        i = i + 1
      end

      ensure_blank()

    elseif is_list_line(line) then
      ensure_blank()

      while i <= #lines and is_list_line(lines[i]) do
        local list_row = i - 1
        emit_page_break(list_row)
        local list_style = style_map[list_row]

        if
          list_style
          and list_style ~= ""
        then
          -- Keep custom paragraph style inside the list item.
          local prefix, body = lines[i]:match("^(%s*[-+*]%s+)(.*)$")

          if not prefix then
            prefix, body = lines[i]:match(
              "^(%s*%d+[%.%)]%s+)(.*)$"
            )
          end

          if prefix then
            table.insert(
              result,
              prefix
                .. '::: {custom-style="'
                .. list_style
                .. '"}'
            )
            table.insert(result, "    " .. (body or ""))
            table.insert(result, "    :::")
          else
            table.insert(result, lines[i])
          end
        else
          table.insert(result, lines[i])
        end

        i = i + 1
      end

      ensure_blank()

    else
      emit_page_break(row)
      ensure_blank()

      local style_name = style_map[row]
      local paragraph_lines = { line }

      -- Shift+Enter continuation lines belong to the same Word
      -- paragraph. They are recognized by two trailing spaces.
      while
        i < #lines
        and hard_break(paragraph_lines[#paragraph_lines])
      do
        i = i + 1
        table.insert(paragraph_lines, lines[i])
      end

      if
        style_name
        and style_name ~= ""
      then
        -- Explicit styles, INCLUDING "Normal", must be written.
        -- Without an explicit Normal custom style, Pandoc can fall
        -- back to the reference document's body paragraph style
        -- (commonly Body Text).
        table.insert(
          result,
          '::: {custom-style="' .. style_name .. '"}'
        )

        for _, paragraph_line in ipairs(paragraph_lines) do
          table.insert(
            result,
            paragraph_line == "" and EMPTY_PARAGRAPH_MARKER or paragraph_line
          )
        end

        table.insert(result, ":::")
      else
        for _, paragraph_line in ipairs(paragraph_lines) do
          table.insert(
            result,
            paragraph_line == "" and EMPTY_PARAGRAPH_MARKER or paragraph_line
          )
        end
      end

      ensure_blank()
      i = i + 1
    end
  end

  -- Do not leave excessive trailing blank lines.
  while #result > 0 and result[#result] == "" do
    table.remove(result)
  end

  return result
end

-- ============================================================
-- Write one real Word style into styles.xml
-- ============================================================

local function write_word_style(docx, spec)
  local function b(value)
    return value and "true" or "false"
  end

  local path = ps_escape(docx)
  local name = ps_escape(spec.name)
  local style_id = ps_escape(spec.id)
  local style_type = ps_escape(spec.type or "paragraph")
  local based_on = ps_escape(spec.based_on or "")
  local font = ps_escape(spec.font or "")
  local size = ps_escape(spec.size or "")
  local color = ps_escape((spec.color or ""):gsub("#", ""))
  local alignment = ps_escape(spec.alignment or "")
  local before = ps_escape(spec.before or "")
  local after = ps_escape(spec.after or "")

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$path = '%s'
$name = '%s'
$styleId = '%s'
$type = '%s'
$basedName = '%s'
$font = '%s'
$size = '%s'
$bold = [bool]::Parse('%s')
$italic = [bool]::Parse('%s')
$underline = [bool]::Parse('%s')
$color = '%s'
$alignment = '%s'
$before = '%s'
$after = '%s'

$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) (
    'wordvim_style_' + [Guid]::NewGuid().ToString('N')
)
$rebuilt = $path + '.wordvim-rebuilt'

try {
    [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory(
        $path,
        $tempDir
    )

    $stylesPath = Join-Path $tempDir 'word\styles.xml'

    if (-not (Test-Path -LiteralPath $stylesPath)) {
        throw 'word/styles.xml not found'
    }

    [xml]$xml = [System.IO.File]::ReadAllText($stylesPath)

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    function New-WElement([string]$local) {
        return $xml.CreateElement('w', $local, $nsUri)
    }

    function Ensure-Child($parent, [string]$local) {
        $node = $parent.SelectSingleNode('w:' + $local, $ns)

        if ($null -eq $node) {
            $node = New-WElement $local
            [void]$parent.AppendChild($node)
        }

        return $node
    }

    function Remove-Child($parent, [string]$local) {
        $node = $parent.SelectSingleNode('w:' + $local, $ns)

        if ($null -ne $node) {
            [void]$parent.RemoveChild($node)
        }
    }

    $style = $null

    foreach ($candidate in $xml.SelectNodes('//w:style', $ns)) {
        if ($candidate.GetAttribute('styleId', $nsUri) -eq $styleId) {
            $style = $candidate
            break
        }
    }

    if ($null -eq $style) {
        $style = New-WElement 'style'
        $style.SetAttribute('type', $nsUri, $type)
        $style.SetAttribute('styleId', $nsUri, $styleId)
        [void]$xml.DocumentElement.AppendChild($style)
    }

    $style.SetAttribute('type', $nsUri, $type)

    $nameNode = Ensure-Child $style 'name'
    $nameNode.SetAttribute('val', $nsUri, $name)

    if ([string]::IsNullOrWhiteSpace($basedName)) {
        Remove-Child $style 'basedOn'
    }
    else {
        $basedId = $basedName

        foreach ($candidate in $xml.SelectNodes('//w:style', $ns)) {
            $candidateName = $candidate.SelectSingleNode('w:name', $ns)

            if (
                $null -ne $candidateName -and
                $candidateName.GetAttribute('val', $nsUri) -eq $basedName
            ) {
                $basedId = $candidate.GetAttribute('styleId', $nsUri)
                break
            }
        }

        $based = Ensure-Child $style 'basedOn'
        $based.SetAttribute('val', $nsUri, $basedId)
    }

    $rPr = Ensure-Child $style 'rPr'

    if ([string]::IsNullOrWhiteSpace($font)) {
        Remove-Child $rPr 'rFonts'
    }
    else {
        $fonts = Ensure-Child $rPr 'rFonts'
        $fonts.SetAttribute('ascii', $nsUri, $font)
        $fonts.SetAttribute('hAnsi', $nsUri, $font)
        $fonts.SetAttribute('cs', $nsUri, $font)
    }

    if ([string]::IsNullOrWhiteSpace($size)) {
        Remove-Child $rPr 'sz'
        Remove-Child $rPr 'szCs'
    }
    else {
        $half = [int]([double]$size * 2)

        $sz = Ensure-Child $rPr 'sz'
        $sz.SetAttribute('val', $nsUri, "$half")

        $szCs = Ensure-Child $rPr 'szCs'
        $szCs.SetAttribute('val', $nsUri, "$half")
    }

    if ($bold) {
        [void](Ensure-Child $rPr 'b')
    }
    else {
        Remove-Child $rPr 'b'
    }

    if ($italic) {
        [void](Ensure-Child $rPr 'i')
    }
    else {
        Remove-Child $rPr 'i'
    }

    if ($underline) {
        $u = Ensure-Child $rPr 'u'
        $u.SetAttribute('val', $nsUri, 'single')
    }
    else {
        Remove-Child $rPr 'u'
    }

    if ([string]::IsNullOrWhiteSpace($color)) {
        Remove-Child $rPr 'color'
    }
    else {
        $colorNode = Ensure-Child $rPr 'color'
        $colorNode.SetAttribute('val', $nsUri, $color)
    }

    if ($type -eq 'paragraph') {
        $pPr = Ensure-Child $style 'pPr'

        if ([string]::IsNullOrWhiteSpace($alignment)) {
            Remove-Child $pPr 'jc'
        }
        else {
            $jc = Ensure-Child $pPr 'jc'
            $jc.SetAttribute('val', $nsUri, $alignment)
        }

        $spacing = $pPr.SelectSingleNode('w:spacing', $ns)

        if (
            [string]::IsNullOrWhiteSpace($before) -and
            [string]::IsNullOrWhiteSpace($after)
        ) {
            if ($null -ne $spacing) {
                [void]$pPr.RemoveChild($spacing)
            }
        }
        else {
            if ($null -eq $spacing) {
                $spacing = New-WElement 'spacing'
                [void]$pPr.AppendChild($spacing)
            }

            if ([string]::IsNullOrWhiteSpace($before)) {
                $spacing.RemoveAttribute('before', $nsUri)
            }
            else {
                $beforeTwips = [int]([double]$before * 20)
                $spacing.SetAttribute('before', $nsUri, "$beforeTwips")
            }

            if ([string]::IsNullOrWhiteSpace($after)) {
                $spacing.RemoveAttribute('after', $nsUri)
            }
            else {
                $afterTwips = [int]([double]$after * 20)
                $spacing.SetAttribute('after', $nsUri, "$afterTwips")
            }
        }
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $false

    $writer = [System.Xml.XmlWriter]::Create($stylesPath, $settings)

    try {
        $xml.Save($writer)
    }
    finally {
        $writer.Dispose()
    }

    if (Test-Path -LiteralPath $rebuilt) {
        Remove-Item -LiteralPath $rebuilt -Force
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $tempDir,
        $rebuilt,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    # Replace only after a completely new valid ZIP has been built.
    [System.IO.File]::Copy($rebuilt, $path, $true)
}
finally {
    if (Test-Path -LiteralPath $rebuilt) {
        Remove-Item -LiteralPath $rebuilt -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
]],
    path,
    name,
    style_id,
    style_type,
    based_on,
    font,
    size,
    b(spec.bold),
    b(spec.italic),
    b(spec.underline),
    color,
    alignment,
    before,
    after
  )

  local ok, output = run_powershell(script)

  if not ok then
    vim.notify(
      "Word Vim: could not update Word style:\n" .. output,
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

local function apply_style_changes(buf, reference_docx)
  for _, spec in pairs(styles.get_style_changes(buf)) do
    if not write_word_style(reference_docx, spec) then
      return false
    end
  end

  return true
end

-- ============================================================
-- Open DOCX
-- ============================================================

local function open_docx(args)
  local buf = args.buf
  local docx = vim.api.nvim_buf_get_name(buf)

  if docx == "" then
    return
  end

  styles.reset_buffer(buf)

  -- Read styles from a COPY, never by reopening the live DOCX.
  local cached_styles = read_word_styles_from_copy(docx)
  styles.set_cached_styles(buf, cached_styles)
  styles.ensure_underline_style(buf)

  local temp_md = vim.fn.tempname() .. ".md"

  -- Extract embedded DOCX images to a temporary directory.
  -- The directory remains available while this buffer is open,
  -- so Pandoc can read the images again when :w is executed.
  local media_dir = vim.fn.tempname() .. "_wordvim_media"
  vim.fn.mkdir(media_dir, "p")
  vim.b[buf].wordvim_media_dir = media_dir

  local pandoc_docx, marker_err =
    make_pandoc_read_copy_with_empty_markers(docx)

  if not pandoc_docx then
    vim.fn.delete(temp_md)
    if vim.b[buf].wordvim_media_dir then
      vim.fn.delete(vim.b[buf].wordvim_media_dir, "rf")
      vim.b[buf].wordvim_media_dir = nil
    end
    vim.notify(
      "Word Vim: could not prepare DOCX for reading empty paragraphs:\n"
        .. tostring(marker_err),
      vim.log.levels.ERROR
    )
    return
  end

  local output = vim.fn.system({
    "pandoc",
    pandoc_docx,
    "--from=docx+styles",
    "--to=" .. markdown_format,
    "--wrap=none",
    "--extract-media=" .. media_dir,
    "--output=" .. temp_md,
  })

  vim.fn.delete(pandoc_docx)

  if vim.v.shell_error ~= 0 then
    vim.fn.delete(temp_md)
    if vim.b[buf].wordvim_media_dir then
      vim.fn.delete(vim.b[buf].wordvim_media_dir, "rf")
      vim.b[buf].wordvim_media_dir = nil
    end
    vim.notify(
      "Word Vim: DOCX conversion failed:\n" .. output,
      vim.log.levels.ERROR
    )
    return
  end

  local raw_lines = vim.fn.readfile(temp_md)
  vim.fn.delete(temp_md)

  local lines, assignments = clean_style_blocks(raw_lines)

  -- Keep the Neovim view compact: Word paragraphs are adjacent
  -- editor rows, without visible empty separator rows.
  lines, assignments = compact_editor_lines(lines, assignments)

  -- Convert Pandoc Markdown list markers to Word Vim's readable
  -- four-level display (1 / 1.1 / ... and custom bullets).
  lines = lists.to_editor_lines(lines)

  -- Collapse a real Word TOC field back to one editor anchor row.
  -- The entries themselves are rendered as virtual lines by toc.lua.
  lines, assignments =
    toc.restore_editor_lines(
      buf,
      lines,
      assignments,
      docx
    )

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Do NOT create the TOC extmark yet.  Several restore steps below
  -- still rewrite buffer lines (notably list-level restoration and
  -- indent cleanup).  With right_gravity=true those rewrites can move
  -- the TOC anchor away from its title.  Keep only pending_open state
  -- until all structural buffer edits are complete.

  -- Pandoc may flatten nested DOCX list levels in Markdown.
  -- Restore the authoritative list level directly from w:ilvl so
  -- Neovim shows • / ◦ / ▪ / ▫ correctly after reopening.
  lists.load_levels_from_docx(buf, docx)

  for _, item in ipairs(assignments) do
    styles.set_paragraph_style(buf, item.row, item.style)
  end

  -- Read real leading Word TABs and paragraph left indents,
  -- then display both visually without arrow symbols.
  indents.load_from_docx(buf, docx)

  -- Pandoc may expose Word paragraph indentation as visible Markdown
  -- blockquote markers (">").  The true indent has already been read
  -- from word/document.xml, so remove those editor-only artifacts.
  indents.clean_editor_indent_markers(buf)

  -- Migrate literal leading TABs left by older Word Vim versions
  -- into hidden Word-tab metadata.
  indents.migrate_legacy_leading_tabs(buf)

  -- Mark the buffer before assigning markdown filetype so future
  -- Markdown-specific plugins can distinguish DOCX from real .md files.
  vim.b[buf].wordvim_docx = true
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].modified = false

  vim.b[buf].docx_original_file = docx
  apply_docx_buffer_profile(buf)

  -- Restore real Word page breaks and page layout settings.
  pagebreaks.load_from_docx(buf, docx)
  pagesettings.load_from_docx(buf, docx)

  -- Restore Word Caption / REF / PAGEREF metadata after Pandoc conversion.
  crossrefs.restore_from_docx(buf, docx)

  -- All buffer-rewriting import/cleanup passes are complete now.
  -- Create the TOC anchor only at this point so right_gravity=true can
  -- safely keep the title + virtual TOC together during normal editing
  -- (for example Shift+O above the TOC title) without the anchor being
  -- displaced by initialization-time whole-buffer rewrites.
  toc.finish_open(buf)

  vim.bo[buf].modified = false

  -- Apply the DOCX-local window profile (wrap, relative numbers,
  -- no sign column, and Word Vim statusline).
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    apply_docx_window_profile(buf, win)
  end

  -- Formatting/headings/lists are DOCX-buffer-local.
  formatting.attach(buf)
  styleui.attach(buf)
  images.attach(buf)

  -- Enable Word-like Enter / Shift+Enter behavior.
  paragraphs.attach(buf)

  -- Insert mode: Word TABs. Normal mode: paragraph indent.
  indents.attach(buf)

  -- Manual page breaks + page setup.
  pagebreaks.attach(buf)
  pagesettings.attach(buf)

  -- Table of Contents.
  toc.attach(buf)

  -- Figure/Table captions and cross-references.
  crossrefs.attach(buf)

  vim.notify(
    "Word Vim: DOCX opened. Word styles cached: " .. #cached_styles,
    vim.log.levels.INFO
  )
end

-- ============================================================
-- Save DOCX
-- ============================================================


local function validate_docx_with_pandoc(path)
  local temp_txt = vim.fn.tempname() .. ".txt"

  local output = vim.fn.system({
    "pandoc",
    path,
    "--to=plain",
    "--output=" .. temp_txt,
  })

  local ok = vim.v.shell_error == 0

  vim.fn.delete(temp_txt)

  if not ok then
    return false, output
  end

  return true
end


local function replace_file_safely(new_docx, original)
  local stage = original .. ".wordvim-new.docx"

  pcall(vim.fn.delete, stage)

  local copied, copy_err = copy_file(new_docx, stage)

  if not copied then
    return false,
      "could not create staging file: " .. tostring(copy_err),
      stage
  end

  local source = ps_escape(stage)
  local target = ps_escape(original)
  local swap_backup = ps_escape(original .. ".wordvim-swap-backup")

  local script = string.format([[
$source = '%s'
$target = '%s'
$swapBackup = '%s'
$lastError = ''

for ($i = 0; $i -lt 12; $i++) {
    try {
        if (Test-Path -LiteralPath $swapBackup) {
            Remove-Item -LiteralPath $swapBackup -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $target) {
            [System.IO.File]::Replace(
                $source,
                $target,
                $swapBackup,
                $true
            )
        }
        else {
            [System.IO.File]::Move($source, $target)
        }

        if (Test-Path -LiteralPath $swapBackup) {
            Remove-Item -LiteralPath $swapBackup -Force -ErrorAction SilentlyContinue
        }

        exit 0
    }
    catch {
        $lastError = $_.Exception.Message
        Start-Sleep -Milliseconds 250
    }
}

Write-Error $lastError
exit 1
]], source, target, swap_backup)

  local ok, output = run_powershell(script)

  if not ok then
    return false, output, stage
  end

  return true, nil, stage
end

local function save_docx(args)
  local buf = args.buf
  local original = vim.b[buf].docx_original_file

  if not original then
    return
  end

  if not create_backup(original) then
    return
  end

  local temp_md = vim.fn.tempname() .. ".md"
  local temp_docx = vim.fn.tempname() .. ".docx"
  local temp_reference = vim.fn.tempname() .. ".docx"

  local copied, copy_err = copy_file(original, temp_reference)
  if not copied then
    vim.notify(
      "Word Vim: could not create reference DOCX:\n" .. tostring(copy_err),
      vim.log.levels.ERROR
    )
    return
  end

  if not apply_style_changes(buf, temp_reference) then
    vim.fn.delete(temp_reference)
    return
  end

  local lines = build_markdown_for_save(buf)
  vim.fn.writefile(lines, temp_md)

  local output = vim.fn.system({
    "pandoc",
    temp_md,
    "--from=" .. markdown_format,
    "--to=docx",
    "--reference-doc=" .. temp_reference,
    "--output=" .. temp_docx,
  })

  vim.fn.delete(temp_md)
  vim.fn.delete(temp_reference)

  if vim.v.shell_error ~= 0 then
    vim.fn.delete(temp_docx)
    vim.notify(
      "Word Vim: DOCX save failed:\n" .. output,
      vim.log.levels.ERROR
    )
    return
  end

  -- Inject real <w:tab/> elements and paragraph w:ind after Pandoc creates DOCX.
  if not indents.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Configure four-level ordered and bullet numbering in numbering.xml.
  if not lists.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Convert Word Vim marker paragraphs into real Word page breaks.
  if not pagebreaks.apply_to_docx(temp_docx) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Apply paper size, orientation and margins.
  if not pagesettings.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Replace caption/reference markers with real Word SEQ / REF / PAGEREF fields.
  if not crossrefs.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Replace the Word Vim TOC marker with a real Word TOC field.
  if not toc.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Turn temporary marker text back into genuine empty Word paragraphs.
  -- The paragraph nodes themselves are kept, so blank paragraphs survive
  -- save -> close -> reopen instead of being treated as Markdown separators.
  if not remove_empty_paragraph_markers(temp_docx) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Never replace the user's original file until Pandoc can read
  -- the final modified DOCX again.
  local valid, validation_error =
    validate_docx_with_pandoc(temp_docx)

  if not valid then
    vim.fn.delete(temp_docx)

    vim.notify(
      "Word Vim: final DOCX validation failed. Original file was NOT replaced.\n"
        .. tostring(validation_error),
      vim.log.levels.ERROR
    )
    return
  end

  local replaced, replace_err, stage =
    replace_file_safely(temp_docx, original)

  vim.fn.delete(temp_docx)

  if not replaced then
    vim.notify(
      "Word Vim: new DOCX was created, but the original file is locked.\n"
        .. tostring(replace_err)
        .. "\n\nThe new file was preserved here:\n"
        .. tostring(stage)
        .. "\n\nClose LibreOffice/OnlyOffice/Explorer preview and run :w again.",
      vim.log.levels.ERROR
    )
    return
  end

  vim.bo[buf].modified = false
  vim.notify("Word Vim: DOCX saved", vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "*.docx",
    callback = open_docx,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    pattern = "*.docx",
    callback = save_docx,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "*.docx",
    callback = function(args)
      if vim.b[args.buf].wordvim_docx then
        apply_docx_buffer_profile(args.buf)
        apply_docx_window_profile(args.buf, vim.api.nvim_get_current_win())
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    pattern = "*.docx",
    callback = function()
      restore_window_profile(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    pattern = "*.docx",
    callback = function(args)
      paragraphs.detach(args.buf)
      pagebreaks.detach(args.buf)
      pagesettings.detach(args.buf)
      toc.detach(args.buf)
      crossrefs.detach(args.buf)

      local media_dir = vim.b[args.buf].wordvim_media_dir
      if media_dir and media_dir ~= "" then
        pcall(vim.fn.delete, media_dir, "rf")
      end
    end,
  })

  vim.api.nvim_create_user_command("WordHelp", function()
    local lines = {
      "WORD VIM",
      "========",
      "",
      "Formatting",
      "----------",
      "Visual + Space b   Bold",
      "Visual + Space i   Italic",
      "Visual + Space u   Underline",
      "Visual + Space s   Strikeout",
      "",
      "Headings",
      "--------",
      "Space 1..6        Heading 1..6",
      "",
      "Lists",
      "-----",
      "Space l b         Bullet list",
      "Space l n         Numbered list",
      "",
      "Pages",
      "-----",
      "Space p b         Insert page break before paragraph",
      "Space p d         Delete page break before paragraph",
      "Space p s         Page Setup",
      ":WordPageBreak",
      ":WordPageBreakDelete",
      ":WordPageSetup",
      "",
      "Captions / Cross-references",
      "---------------------------",
      "Space c f         Figure caption",
      "Space c t         Table caption",
      "Space r f         Reference to Figure",
      "Space r t         Reference to Table",
      ":WordCaptionFigure / :WordCaptionTable",
      ":WordRefFigure / :WordRefTable",
      "",
      "Table of Contents",
      "-----------------",
      "Space t c         Insert contents",
      "Space t d         Delete contents",
      "Space t o         Toggle contents window",
      ":WordTOC",
      ":WordTOCDelete",
      ":WordTOCRefresh",
      ":WordTOCWindow",
      "",
      "Tables",
      "------",
      ":WordTable",
      ":WordTable 5 4",
      "",
      "Images",
      "------",
      "Space i i          Telescope image picker",
      ":WordImagePicker",
      ":WordImage",
      ":WordImage C:\\Users\\Leo\\Pictures\\photo.png",
      ":WordImageWidth 8cm",
      ":WordImageScale 50",
      ":WordImageResize 125",
      ":WordImageRotate 90",
      ":WordImageRotate 180",
      ":WordImageRotate 270",
      ":WordImageReset",
      "",
      "Styles",
      "------",
      ":WordStyle        Show current paragraph style",
      ":WordStyles       Choose/apply a paragraph style",
      ":WordStyleApply Body Text",
      ":WordStyleEdit Normal",
      ":WordStyleEdit Heading 1",
      ":WordStyleNew",
      "",
      "Style UI",
      "--------",
      "Space w s          Toggle both style panels",
      ":WordStyleUI       Open both style panels",
      ":WordStyleUIClose  Close both style panels",
      ":WordStyleUIToggle Toggle both style panels",
      "",
      "Save",
      "----",
      ":w",
    }

    vim.cmd("new")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    vim.bo.modifiable = false
  end, {})
end

return M
