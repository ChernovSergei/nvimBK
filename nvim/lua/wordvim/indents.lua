-- ============================================================
-- lua/wordvim/indents.lua
--
-- Word-like TAB behavior.
--
-- Goal:
--   Tab in Neovim should look like an indentation step,
--   but in DOCX it must be a REAL Word tab character so
--   LibreOffice/Word shows the blue tab arrow when formatting
--   marks are enabled.
--
-- Implementation:
--   * Leading Word tabs are stored as hidden extmark metadata.
--   * Tabs between words are ordinary literal TAB characters in the editor,
--     so Name<Tab>Value visibly behaves like a real tab stop.
--   * Neovim displays them as virtual spaces (no arrow symbols).
--   * The Markdown text itself is NOT prefixed with literal tabs,
--     so Pandoc does not accidentally turn paragraphs into code.
--   * After Pandoc creates the DOCX, Word Vim injects <w:tab/>
--     elements at the start of the matching Word paragraph.
--   * On open, Word Vim reads leading <w:tab/> elements back.
--
-- Keys:
--   Insert mode Tab        = insert a genuine Word tab at cursor
--   Insert mode Backspace  = remove one leading Word tab at row start
--   Insert mode Shift+Tab  = remove one leading Word tab
--   Normal mode Tab        = increase paragraph left indent
--   Normal mode Shift+Tab  = decrease paragraph left indent
-- ============================================================

local M = {}

local namespace =
  vim.api.nvim_create_namespace("WordVimLeadingTabs")

local display_namespace =
  vim.api.nvim_create_namespace("WordVimLeadingTabsDisplay")

local indent_namespace =
  vim.api.nvim_create_namespace("WordVimParagraphIndent")

local state = {}
local indent_state = {}

local DISPLAY_SPACES_PER_TAB = 4
local INLINE_TAB_MARKER = "WORDVIM_INLINE_TAB_5F83A1D4"
local INDENT_STEP_TWIPS = 708
local DISPLAY_SPACES_PER_INDENT = 4

local function get_state(buf)
  if not state[buf] then
    state[buf] = {
      marks = {},
    }
  end

  return state[buf]
end

local function get_indent_state(buf)
  if not indent_state[buf] then
    indent_state[buf] = { marks = {} }
  end

  return indent_state[buf]
end

local function ps_escape(value)
  return tostring(value or ""):gsub("'", "''")
end

local function run_powershell(script)
  return require("wordvim.runtime").run_powershell(script)
end

local function normalize_text(text)
  text = tostring(text or "")

  -- Pandoc can represent Word paragraph left indentation as Markdown
  -- block quote syntax (for example "> Father").  The real indent is
  -- tracked separately from word/document.xml, so ignore those
  -- markers when matching DOCX paragraphs to editor rows.
  text = text:gsub("^%s*>+%s*", "")

  text = text:gsub("^%s*#+%s*", "")
  text = text:gsub("^%s*[-+*]%s+", "")
  text = text:gsub("^%s*%d+[%.%)]%s+", "")

  text = text:gsub("\\([\\`*_{}%[%]()#+%.!<>%-])", "%1")

  text = text:gsub("%*%*", "")
  text = text:gsub("__", "")
  text = text:gsub("~~", "")
  text = text:gsub("`", "")

  text = text:gsub("%]%b{}", "]")

  text = text:gsub("!%[.-%]%b()", "")
  text = text:gsub("%[([^%]]+)%]%b()", "%1")

  text = vim.trim(text)
  text = text:gsub("%s+", " ")

  return text
end

local function decode_b64(value)
  if value == "" then
    return ""
  end

  local ok, result = pcall(vim.base64.decode, value)
  if ok then
    return result
  end

  return ""
end

local function encode_b64(value)
  return vim.base64.encode(tostring(value or ""))
end

local function delete_row_mark(buf, row)
  local s = get_state(buf)

  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    namespace,
    { row, 0 },
    { row, -1 },
    {}
  )

  for _, mark in ipairs(marks) do
    s.marks[mark[1]] = nil
    pcall(
      vim.api.nvim_buf_del_extmark,
      buf,
      namespace,
      mark[1]
    )
  end
end

local function set_tab_count(buf, row, count, explicit)
  count = math.max(0, tonumber(count) or 0)

  delete_row_mark(buf, row)

  if count == 0 and not explicit then
    return
  end

  local id = vim.api.nvim_buf_set_extmark(
    buf,
    namespace,
    row,
    0,
    {
      -- Leading-tab metadata belongs to the paragraph text.  When a new
      -- paragraph is inserted immediately before this row (O, o on the
      -- previous row, paste, etc.), keep the extmark attached to the
      -- original paragraph instead of leaving it on the newly inserted row.
      right_gravity = true,
      end_row = math.min(row + 1, vim.api.nvim_buf_line_count(buf)),
      end_col = 0,
      end_right_gravity = false,
      invalidate = true,
      undo_restore = true,
    }
  )

  get_state(buf).marks[id] = {
    count = count,
    explicit = explicit == true,
  }
end

local function delete_indent_mark(buf, row)
  local s = get_indent_state(buf)
  local marks = vim.api.nvim_buf_get_extmarks(
    buf, indent_namespace, { row, 0 }, { row, -1 }, {}
  )

  for _, mark in ipairs(marks) do
    s.marks[mark[1]] = nil
    pcall(vim.api.nvim_buf_del_extmark, buf, indent_namespace, mark[1])
  end
end

local function set_paragraph_indent(buf, row, left, explicit)
  left = math.max(0, tonumber(left) or 0)
  delete_indent_mark(buf, row)

  if left == 0 and not explicit then
    return
  end

  local id = vim.api.nvim_buf_set_extmark(
    buf, indent_namespace, row, 0, {
      -- Paragraph-indent metadata must move with the original paragraph when
      -- rows are inserted before it.  This mirrors paragraph-style extmarks.
      right_gravity = true,
      end_row = math.min(row + 1, vim.api.nvim_buf_line_count(buf)),
      end_col = 0,
      end_right_gravity = false,
      invalidate = true,
      undo_restore = true,
    }
  )

  get_indent_state(buf).marks[id] = {
    left = left,
    explicit = explicit == true,
  }
end

function M.get_paragraph_indent(buf, row)
  local s = get_indent_state(buf)
  local marks = vim.api.nvim_buf_get_extmarks(
    buf, indent_namespace, { row, 0 }, { row, -1 }, {}
  )

  for _, mark in ipairs(marks) do
    local item = s.marks[mark[1]]
    if item then
      return item.left or 0, item.explicit == true
    end
  end

  return 0, false
end

function M.reset_buffer(buf)
  state[buf] = { marks = {} }
  indent_state[buf] = { marks = {} }

  vim.api.nvim_buf_clear_namespace(
    buf,
    namespace,
    0,
    -1
  )

  vim.api.nvim_buf_clear_namespace(
    buf,
    display_namespace,
    0,
    -1
  )

  vim.api.nvim_buf_clear_namespace(
    buf,
    indent_namespace,
    0,
    -1
  )
end

function M.get_tab_count(buf, row)
  local s = get_state(buf)

  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    namespace,
    { row, 0 },
    { row, -1 },
    {}
  )

  for _, mark in ipairs(marks) do
    local item = s.marks[mark[1]]

    if item then
      return item.count or 0, item.explicit == true
    end
  end

  return 0, false
end

local function purge_invalid_metadata(buf)
  local function purge(ns, state)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if details.invalid then
        state.marks[mark[1]] = nil
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, mark[1])
      end
    end
  end

  purge(namespace, get_state(buf))
  purge(indent_namespace, get_indent_state(buf))
end

function M.refresh_display(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  purge_invalid_metadata(buf)

  vim.api.nvim_buf_clear_namespace(
    buf,
    display_namespace,
    0,
    -1
  )

  vim.api.nvim_set_hl(
    0,
    "WordVimIndentLevel",
    {
      fg = "#7AA2F7",
      bold = true,
    }
  )

  local count = vim.api.nvim_buf_line_count(buf)

  for row = 0, count - 1 do
    local tabs = M.get_tab_count(buf, row)
    local left = M.get_paragraph_indent(buf, row)

    local tab_spaces =
      tabs * DISPLAY_SPACES_PER_TAB

    local indent_level =
      math.max(
        0,
        math.floor(
          (left / INDENT_STEP_TWIPS) + 0.5
        )
      )

    local indent_spaces =
      math.max(
        0,
        math.floor(
          (left / INDENT_STEP_TWIPS)
            * DISPLAY_SPACES_PER_INDENT
          + 0.5
        )
      )

    local chunks = {}

    if indent_level > 0 then
      local label =
        tostring(indent_level) .. "│"

      local remaining =
        math.max(
          1,
          indent_spaces - vim.fn.strdisplaywidth(label)
        )

      table.insert(
        chunks,
        {
          label,
          "WordVimIndentLevel",
        }
      )

      table.insert(
        chunks,
        {
          string.rep(" ", remaining),
          "Whitespace",
        }
      )
    elseif indent_spaces > 0 then
      table.insert(
        chunks,
        {
          string.rep(" ", indent_spaces),
          "Whitespace",
        }
      )
    end

    if tab_spaces > 0 then
      table.insert(
        chunks,
        {
          string.rep(" ", tab_spaces),
          "Whitespace",
        }
      )
    end

    if #chunks > 0 then
      vim.api.nvim_buf_set_extmark(
        buf,
        display_namespace,
        row,
        0,
        {
          virt_text = chunks,
          virt_text_pos = "inline",
          right_gravity = false,
          priority = 40,
        }
      )
    end
  end
end

function M.clean_editor_indent_markers(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local count =
    vim.api.nvim_buf_line_count(buf)

  local previous_indent_level = 0

  for row = 0, count - 1 do
    local line =
      vim.api.nvim_buf_get_lines(
        buf,
        row,
        row + 1,
        false
      )[1] or ""

    local left =
      M.get_paragraph_indent(buf, row)

    local current_level =
      math.max(
        0,
        math.floor(
          (left / INDENT_STEP_TWIPS) + 0.5
        )
      )

    -- Count one or more visible Pandoc blockquote markers.
    -- Examples:
    --   > text
    --   > > text
    --   >> text
    local remaining = line
    local marker_count = 0

    while remaining:match("^%s*>%s*") do
      remaining =
        remaining:gsub("^%s*>%s*", "", 1)

      marker_count = marker_count + 1
    end

    if marker_count > 0 then
      local inferred_level = marker_count

      -- In compact Pandoc output a nested indented paragraph can
      -- remain as a single visible ">" after the previous paragraph
      -- has already been resolved from word/document.xml.
      --
      -- Example:
      --   Father  -> DOCX indent level 1
      --   > Brather
      --
      -- Treat that remaining marker as one level deeper.
      if
        current_level == 0
        and previous_indent_level > 0
        and marker_count == 1
      then
        inferred_level =
          previous_indent_level + 1
      end

      local final_level =
        math.max(
          current_level,
          inferred_level
        )

      set_paragraph_indent(
        buf,
        row,
        final_level * INDENT_STEP_TWIPS,
        false
      )

      vim.api.nvim_buf_set_lines(
        buf,
        row,
        row + 1,
        false,
        { remaining }
      )

      current_level = final_level
    end

    if current_level > 0 then
      previous_indent_level = current_level
    else
      previous_indent_level = 0
    end
  end

  M.refresh_display(buf)
end

function M.change_tab_count(buf, row, delta)
  local current = M.get_tab_count(buf, row)
  local next_count = math.max(0, current + delta)

  set_tab_count(
    buf,
    row,
    next_count,
    true
  )

  M.refresh_display(buf)
  vim.bo[buf].modified = true

  pcall(
    vim.api.nvim_exec_autocmds,
    "User",
    {
      pattern = "WordVimIndentChanged",
      modeline = false,
      data = {
        buf = buf,
        row = row,
      },
    }
  )
end

function M.change_paragraph_indent(buf, row, delta_steps)
  local current = M.get_paragraph_indent(buf, row)
  local next_left = math.max(0, current + delta_steps * INDENT_STEP_TWIPS)

  set_paragraph_indent(buf, row, next_left, true)
  M.refresh_display(buf)
  vim.bo[buf].modified = true

  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WordVimIndentChanged",
    modeline = false,
    data = { buf = buf, row = row },
  })
end

function M.copy_indent(buf, from_row, to_row)
  local count = M.get_tab_count(buf, from_row)
  local left = M.get_paragraph_indent(buf, from_row)

  if count > 0 then
    set_tab_count(buf, to_row, count, true)
  end

  if left > 0 then
    set_paragraph_indent(buf, to_row, left, true)
  end

  if count > 0 or left > 0 then
    M.refresh_display(buf)
  end
end

-- ------------------------------------------------------------
-- Read leading Word tabs from original DOCX.
-- ------------------------------------------------------------

function M.load_from_docx(buf, docx)
  M.reset_buffer(buf)

  local temp_docx =
    vim.fn.tempname() .. ".docx"

  -- Copy the live DOCX first so LibreOffice/Word can keep the original open.
  local copied, copy_output = vim.uv.fs_copyfile(docx,temp_docx)

  if not copied then
    pcall(vim.fn.delete, temp_docx)

    vim.notify(
      "Word Vim: could not make a temporary DOCX copy for reading tabs/indents:\n"
        .. tostring(copy_output),
      vim.log.levels.WARN
    )

    return
  end

  local path = ps_escape(temp_docx)

  -- Keep PowerShell syntax deliberately simple and conventional.
  -- Avoid multiline boolean expressions because Windows PowerShell 5.1
  -- is very sensitive to line breaks around operators such as -and.
  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$zip = $null
$reader = $null

try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zip.GetEntry('word/document.xml')

    if ($null -eq $entry) {
        exit 0
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
    $reader.Close()
    $reader = $null

    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $paragraphs = $xml.SelectNodes('/w:document/w:body/w:p', $ns)

    foreach ($p in $paragraphs) {
        $textParts = @()

        foreach ($t in $p.SelectNodes('.//w:t', $ns)) {
            $textParts += $t.InnerText
        }

        $text = ($textParts -join '')

        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $leadingTabs = 0
        $seenText = $false
        $runs = @($p.SelectNodes('w:r', $ns))

        foreach ($run in $runs) {
            $children = @($run.ChildNodes)

            foreach ($child in $children) {
                if ($child.NamespaceURI -ne $nsUri) {
                    continue
                }

                if ($child.LocalName -eq 'tab') {
                    if (-not $seenText) {
                        $leadingTabs++
                    }

                    continue
                }

                if ($child.LocalName -eq 't') {
                    if (-not [string]::IsNullOrEmpty($child.InnerText)) {
                        $seenText = $true
                    }
                }
            }
        }

        $left = 0

        # List indentation belongs to the list level, not to Word Vim's
        # ordinary paragraph-indent metadata.  Otherwise nested lists
        # appear as 1│ / 2│ / 3│ and Normal-mode Tab changes paragraph
        # indent instead of list level.
        $numPr = $p.SelectSingleNode('w:pPr/w:numPr', $ns)

        if ($null -eq $numPr) {
            $ind = $p.SelectSingleNode('w:pPr/w:ind', $ns)

            if ($null -ne $ind) {
                $value = $ind.GetAttribute('left', $nsUri)

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $parsed = 0

                    if ([int]::TryParse($value, [ref]$parsed)) {
                        $left = $parsed
                    }
                }
            }
        }

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $b64 = [Convert]::ToBase64String($bytes)

        Write-Output ($b64 + "`t" + $leadingTabs + "`t" + $left)
    }
}
finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }

    if ($null -ne $zip) {
        $zip.Dispose()
    }
}
]], path)

  local ok, output =
    run_powershell(script)

  pcall(vim.fn.delete, temp_docx)

  if not ok then
    vim.notify(
      "Word Vim: could not read tabs/indents from temporary DOCX copy:\n"
        .. output,
      vim.log.levels.WARN
    )

    return
  end

  local source = {}

  for line in output:gmatch("[^\r\n]+") do
    local b64, tabs, left =
      line:match("^(.-)\t(.-)\t(.-)$")

    if b64 then
      table.insert(
        source,
        {
          text = normalize_text(
            decode_b64(b64)
          ),
          tabs = tonumber(tabs) or 0,
          left = tonumber(left) or 0,
        }
      )
    end
  end

  local editor_count =
    vim.api.nvim_buf_line_count(buf)

  local search_row = 0

  for _, item in ipairs(source) do
    if item.text ~= "" then
      local found = nil

      for row = search_row,
        math.min(
          editor_count - 1,
          search_row + 80
        )
      do
        local editor_text =
          normalize_text(
            vim.api.nvim_buf_get_lines(
              buf,
              row,
              row + 1,
              false
            )[1] or ""
          )

        if editor_text ~= "" and editor_text == item.text then
          found = row
          break
        end
      end

      if found ~= nil then
        if item.tabs > 0 then
          set_tab_count(
            buf,
            found,
            item.tabs,
            false
          )
        end

        if item.left > 0 then
          set_paragraph_indent(
            buf,
            found,
            item.left,
            false
          )
        end

        search_row = found + 1
      end
    end
  end

  M.refresh_display(buf)
end

-- ------------------------------------------------------------
-- Backward compatibility:
-- old Word Vim versions may have placed literal leading tabs
-- into Markdown. Convert them into hidden Word-tab metadata.
-- ------------------------------------------------------------

function M.migrate_legacy_leading_tabs(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return 0
  end

  local count =
    vim.api.nvim_buf_line_count(buf)

  local changed = 0

  for row = 0, count - 1 do
    local line =
      vim.api.nvim_buf_get_lines(
        buf,
        row,
        row + 1,
        false
      )[1] or ""

    local tabs = line:match("^(\t+)")

    if tabs and #tabs > 0 then
      local current =
        M.get_tab_count(buf, row)

      set_tab_count(
        buf,
        row,
        current + #tabs,
        true
      )

      vim.api.nvim_buf_set_lines(
        buf,
        row,
        row + 1,
        false,
        {
          line:gsub("^\t+", "", 1),
        }
      )

      changed = changed + 1
    end
  end

  if changed > 0 then
    M.refresh_display(buf)
    vim.bo[buf].modified = true

    vim.notify(
      "Word Vim: converted "
        .. changed
        .. " legacy leading TAB(s)",
      vim.log.levels.INFO
    )
  end

  return changed
end

-- ------------------------------------------------------------
-- Save leading Word tabs by editing document.xml after Pandoc.
-- ------------------------------------------------------------

local function collect_save_specs(buf)
  local specs = {}
  local occurrences = {}
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  for row = 0, line_count - 1 do
    local line =
      vim.api.nvim_buf_get_lines(
        buf,
        row,
        row + 1,
        false
      )[1] or ""

    local text = normalize_text(line)

    if
      text ~= ""
      and not line:match("^%s*!%[")
    then
      occurrences[text] =
        (occurrences[text] or 0) + 1

      local tabs, tab_explicit = M.get_tab_count(buf, row)
      local left, indent_explicit = M.get_paragraph_indent(buf, row)

      if tabs > 0 or left > 0 or tab_explicit or indent_explicit then
        table.insert(specs, {
          text = text,
          occurrence = occurrences[text],
          count = tabs,
          left = left,
        })
      end
    end
  end

  return specs
end

local function replace_inline_tab_markers(docx)
  local path = ps_escape(docx)
  local marker = ps_escape(INLINE_TAB_MARKER)

  local script = string.format([=[
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$path = '%s'
$marker = '%s'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Update')
    $entry = $zip.GetEntry('word/document.xml')

    if ($null -eq $entry) {
        foreach ($candidate in @($zip.Entries)) {
            $normalized = $candidate.FullName.Replace('\', '/')
            if ($normalized -eq 'word/document.xml') {
                $entry = $candidate
                break
            }
        }
    }

    if ($null -eq $entry) { throw 'word/document.xml not found' }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
    $reader.Close()

    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $nodes = @($xml.SelectNodes('//w:t[contains(text(), "' + $marker + '")]', $ns))

    foreach ($t in $nodes) {
        $run = $t.ParentNode
        if ($null -eq $run -or $run.LocalName -ne 'r') { continue }

        $parts = $t.InnerText.Split([string[]]@($marker), [System.StringSplitOptions]::None)

        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i].Length -gt 0) {
                $newT = $xml.CreateElement('w', 't', $nsUri)
                $newT.InnerText = $parts[$i]
                if ($parts[$i].StartsWith(' ') -or $parts[$i].EndsWith(' ')) {
                    $space = $xml.CreateAttribute('xml', 'space', 'http://www.w3.org/XML/1998/namespace')
                    $space.Value = 'preserve'
                    [void]$newT.Attributes.Append($space)
                }
                [void]$run.InsertBefore($newT, $t)
            }

            if ($i -lt ($parts.Count - 1)) {
                $tab = $xml.CreateElement('w', 'tab', $nsUri)
                [void]$run.InsertBefore($tab, $t)
            }
        }

        [void]$run.RemoveChild($t)
    }

    $oldName = $entry.FullName
    $entry.Delete()
    $newEntry = $zip.CreateEntry('word/document.xml')
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $xml.Save($writer)
    $writer.Close()
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
]=], path, marker)

  local ok, output = run_powershell(script)
  if not ok then
    vim.notify(
      "Word Vim: could not restore inline Word tabs:\n" .. tostring(output),
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

function M.apply_to_docx(docx, buf)
  -- Always process inline TAB tokens, even when the document has no leading
  -- tab/indent metadata at all.
  if not replace_inline_tab_markers(docx) then
    return false
  end

  local specs = collect_save_specs(buf)

  if #specs == 0 then
    return true
  end

  local temp_specs = vim.fn.tempname() .. ".tsv"
  local spec_lines = {}

  for _, spec in ipairs(specs) do
    table.insert(
      spec_lines,
      table.concat({
        encode_b64(spec.text),
        tostring(spec.occurrence),
        tostring(spec.count),
        tostring(spec.left),
      }, "\t")
    )
  end

  vim.fn.writefile(spec_lines, temp_specs)

  local path = ps_escape(docx)
  local specs_path = ps_escape(temp_specs)

  -- IMPORTANT:
  -- Do NOT unpack and rebuild the whole DOCX package.
  -- Open the already-valid Pandoc DOCX in ZipArchive Update mode
  -- and replace ONLY word/document.xml.
  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$specsPath = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

# Read requested leading tab counts.
$targets = @()

$specLines = Get-Content -LiteralPath $specsPath -Encoding UTF8

foreach ($line in $specLines) {
    $fields = $line -split "`t"

    if ($fields.Count -lt 4) {
        continue
    }

    $targetText = [System.Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($fields[0])
    )

    $targets += [PSCustomObject]@{
        Text = $targetText
        Occurrence = [int]$fields[1]
        Count = [int]$fields[2]
        Left = [int]$fields[3]
    }
}

# First read document.xml from the valid DOCX without changing anything.
$zipRead = $null
$reader = $null

try {
    $zipRead = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zipRead.GetEntry('word/document.xml')

    if ($null -eq $entry) {
        throw 'word/document.xml not found'
    }

    $reader = New-Object System.IO.StreamReader(
        $entry.Open(),
        [System.Text.Encoding]::UTF8,
        $true
    )

    $xmlText = $reader.ReadToEnd()
}
finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }

    if ($null -ne $zipRead) {
        $zipRead.Dispose()
    }
}

[xml]$xml = $xmlText

$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('w', $nsUri)

$paragraphs = $xml.SelectNodes('/w:document/w:body/w:p', $ns)
$seen = @{}

foreach ($p in $paragraphs) {
    $parts = @()

    foreach ($t in $p.SelectNodes('.//w:t', $ns)) {
        $parts += $t.InnerText
    }

    $text = ($parts -join '')

    if (-not $seen.ContainsKey($text)) {
        $seen[$text] = 0
    }

    $seen[$text]++

    $target = $null

    foreach ($candidate in $targets) {
        if (
            ($candidate.Text -eq $text) -and
            ($candidate.Occurrence -eq $seen[$text])
        ) {
            $target = $candidate
            break
        }
    }

    if ($null -eq $target) {
        continue
    }

    # Remove existing leading <w:tab/> elements only, before the first
    # real text node.
    $seenRealText = $false
    $runs = @($p.SelectNodes('w:r', $ns))

    foreach ($run in $runs) {
        $children = @($run.ChildNodes)

        foreach ($child in $children) {
            if ($child.NamespaceURI -ne $nsUri) {
                continue
            }

            if (
                ($child.LocalName -eq 'tab') -and
                (-not $seenRealText)
            ) {
                [void]$run.RemoveChild($child)
                continue
            }

            if (
                ($child.LocalName -eq 't') -and
                (-not [string]::IsNullOrEmpty($child.InnerText))
            ) {
                $seenRealText = $true
                break
            }
        }

        if ($seenRealText) {
            break
        }
    }

    if ($target.Count -gt 0) {
        # Insert one run containing N genuine Word tab elements.
        $tabRun = $xml.CreateElement('w', 'r', $nsUri)

        for ($i = 0; $i -lt $target.Count; $i++) {
            $tab = $xml.CreateElement('w', 'tab', $nsUri)
            [void]$tabRun.AppendChild($tab)
        }

        $firstRun = $p.SelectSingleNode('w:r', $ns)

        if ($null -ne $firstRun) {
            [void]$p.InsertBefore($tabRun, $firstRun)
        }
        else {
            [void]$p.AppendChild($tabRun)
        }
    }

    # Apply paragraph left indent for Normal-mode Tab / Shift+Tab.
    $pPr = $p.SelectSingleNode('w:pPr', $ns)

    if ($null -eq $pPr) {
        $pPr = $xml.CreateElement('w', 'pPr', $nsUri)
        [void]$p.PrependChild($pPr)
    }

    $ind = $pPr.SelectSingleNode('w:ind', $ns)

    if ($target.Left -gt 0) {
        if ($null -eq $ind) {
            $ind = $xml.CreateElement('w', 'ind', $nsUri)
            [void]$pPr.AppendChild($ind)
        }

        $ind.SetAttribute('left', $nsUri, [string]$target.Left)
    }
    elseif ($null -ne $ind) {
        $ind.RemoveAttribute('left', $nsUri)

        if ($ind.Attributes.Count -eq 0) {
            [void]$pPr.RemoveChild($ind)
        }
    }
}

# Serialize XML completely in memory.
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$settings.Indent = $false
$settings.OmitXmlDeclaration = $false

$stringBuilder = New-Object System.Text.StringBuilder
$stringWriter = New-Object System.IO.StringWriter($stringBuilder)
$xmlWriter = [System.Xml.XmlWriter]::Create($stringWriter, $settings)

try {
    $xml.Save($xmlWriter)
    $xmlWriter.Flush()
}
finally {
    $xmlWriter.Dispose()
    $stringWriter.Dispose()
}

$newXml = $stringBuilder.ToString()

# Replace ONLY word/document.xml in the existing package.
$fileStream = $null
$zipUpdate = $null
$entryWriter = $null

try {
    $fileStream = [System.IO.File]::Open(
        $path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )

    $zipUpdate = New-Object System.IO.Compression.ZipArchive(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Update,
        $false
    )

    $oldEntry = $zipUpdate.GetEntry('word/document.xml')

    if ($null -eq $oldEntry) {
        throw 'word/document.xml not found during ZIP update'
    }

    $oldEntry.Delete()

    $newEntry = $zipUpdate.CreateEntry(
        'word/document.xml',
        [System.IO.Compression.CompressionLevel]::Optimal
    )

    $entryWriter = New-Object System.IO.StreamWriter(
        $newEntry.Open(),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $entryWriter.Write($newXml)
    $entryWriter.Flush()
}
finally {
    if ($null -ne $entryWriter) {
        $entryWriter.Dispose()
    }

    if ($null -ne $zipUpdate) {
        $zipUpdate.Dispose()
    }

    if ($null -ne $fileStream) {
        $fileStream.Dispose()
    }
}

# Validate the resulting DOCX package immediately.
$zipCheck = $null
$checkReader = $null

try {
    $zipCheck = [System.IO.Compression.ZipFile]::OpenRead($path)

    $required = @(
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml'
    )

    foreach ($requiredName in $required) {
        if ($null -eq $zipCheck.GetEntry($requiredName)) {
            throw ('Required DOCX entry missing: ' + $requiredName)
        }
    }

    $checkEntry = $zipCheck.GetEntry('word/document.xml')

    $checkReader = New-Object System.IO.StreamReader(
        $checkEntry.Open(),
        [System.Text.Encoding]::UTF8,
        $true
    )

    $checkXmlText = $checkReader.ReadToEnd()

    # XML parse itself is another structural validation.
    [xml]$checkXml = $checkXmlText

    if ($null -eq $checkXml.DocumentElement) {
        throw 'word/document.xml is empty or invalid'
    }
}
finally {
    if ($null -ne $checkReader) {
        $checkReader.Dispose()
    }

    if ($null -ne $zipCheck) {
        $zipCheck.Dispose()
    }
}
]], path, specs_path)

  local ok, output = run_powershell(script)

  vim.fn.delete(temp_specs)

  if not ok then
    vim.notify(
      "Word Vim: could not safely write tabs/indents:\n"
        .. output,
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

local function try_change_list_level(buf, row, delta)
  local ok, lists = pcall(require, "wordvim.lists")

  if not ok then
    return false
  end

  local line = vim.api.nvim_buf_get_lines(
    buf,
    row,
    row + 1,
    false
  )[1] or ""

  if not lists.is_list_line(line) then
    return false
  end

  return lists.change_level(buf, row, delta)
end


function M.clear_row_metadata(buf, row)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  delete_row_mark(buf, row)
  delete_indent_mark(buf, row)
end

function M.clear_range_metadata(buf, first_row, last_row)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  first_row = math.max(0, tonumber(first_row) or 0)
  last_row = math.max(first_row, tonumber(last_row) or first_row)

  for row = first_row, last_row do
    M.clear_row_metadata(buf, row)
  end

  M.refresh_display(buf)
end

local function delete_current_lines(buf)
  local row =
    vim.api.nvim_win_get_cursor(0)[1] - 1

  local count =
    math.max(1, vim.v.count1 or 1)

  local last_row =
    math.min(
      vim.api.nvim_buf_line_count(buf) - 1,
      row + count - 1
    )

  -- Paragraph/TAB metadata belongs to the paragraph being deleted.
  -- Remove that metadata BEFORE Vim shifts following lines upward.
  M.clear_range_metadata(
    buf,
    row,
    last_row
  )

  -- Page-break metadata belongs to the deleted paragraph too.
  local ok_pagebreaks, pagebreaks =
    pcall(require, "wordvim.pagebreaks")

  if ok_pagebreaks then
    pagebreaks.clear_range_metadata(
      buf,
      row,
      last_row
    )
  end

  -- Caption / cross-reference metadata also belongs to deleted text.
  local ok_crossrefs, crossrefs =
    pcall(require, "wordvim.crossrefs")

  if ok_crossrefs then
    crossrefs.clear_range_metadata(
      buf,
      row,
      last_row
    )
  end

  local command =
    tostring(count) .. "dd"

  vim.cmd("normal! " .. command)

  M.refresh_display(buf)
end

function M.attach(buf)
  local group = vim.api.nvim_create_augroup("WordVimIndents_" .. tostring(buf), { clear = true })

  -- Native undo/redo changes buffer text but extmark-only metadata does not
  -- create its own undo entry.  Refresh after every text-state change so
  -- invalidated paragraph ranges disappear immediately instead of leaving a
  -- ghost indent marker on an empty/deleted paragraph.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M.refresh_display(buf)
        end
      end)
    end,
  })

  -- INSERT MODE: genuine Word TAB
  vim.keymap.set(
    "i",
    "<Tab>",
    function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local col = cursor[2]

      -- In a list, Tab changes nesting level exactly as before.
      if try_change_list_level(buf, row, 1) then
        return ""
      end

      -- At physical column 0 keep the historical hidden leading Word-tab
      -- behavior so paragraph-leading tabs never turn Markdown into code.
      if col == 0 then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            M.change_tab_count(buf, row, 1)
          end
        end)
        return ""
      end

      -- Between words insert a literal TAB byte directly.  We do not return
      -- the Tab key from this expr mapping because expandtab would turn it
      -- into spaces.  The direct buffer edit preserves a real TAB character.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        vim.api.nvim_buf_set_text(buf, row, col, row, col, { "\t" })

        local win = vim.fn.bufwinid(buf)
        if win ~= -1 and vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col + 1 })
        end
      end)

      return ""
    end,
    {
      buffer = buf,
      expr = true,
      noremap = true,
      silent = true,
      desc = "Word Vim: insert one Word TAB",
    }
  )

  -- INSERT MODE: remove one leading Word TAB.
  vim.keymap.set(
    "i",
    "<S-Tab>",
    function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local col = cursor[2]

      if try_change_list_level(buf, row, -1) then
        return ""
      end

      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""

      -- If the character immediately before the cursor is an inline TAB,
      -- delete that TAB first.
      if col > 0 and line:sub(col, col) == "\t" then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end

          vim.api.nvim_buf_set_text(buf, row, col - 1, row, col, {})

          local win = vim.fn.bufwinid(buf)
          if win ~= -1 and vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col - 1 })
          end
        end)
        return ""
      end

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          M.change_tab_count(buf, row, -1)
        end
      end)

      return ""
    end,
    {
      buffer = buf,
      expr = true,
      noremap = true,
      silent = true,
      desc = "Word Vim: remove one Word TAB",
    }
  )

  -- INSERT MODE: Backspace removes one hidden leading Word TAB
  -- if cursor is at the physical start of the Markdown row.
  -- Otherwise let Neovim handle Backspace normally.
  vim.keymap.set(
    "i",
    "<BS>",
    function()
      local cursor =
        vim.api.nvim_win_get_cursor(0)

      local row = cursor[1] - 1
      local col = cursor[2]

      local tabs =
        M.get_tab_count(buf, row)

      if col == 0 and tabs > 0 then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            M.change_tab_count(
              buf,
              row,
              -1
            )
          end
        end)

        return
      end

      -- IMPORTANT:
      -- Do not return the encoded <BS> key sequence from a callback.
      -- In some terminals that literal termcode can be inserted as text
      -- such as "<80>kb". Feed the actual Backspace key to Neovim instead.
      local key =
        vim.api.nvim_replace_termcodes(
          "<BS>",
          true,
          false,
          true
        )

      vim.api.nvim_feedkeys(
        key,
        "n",
        true
      )
    end,
    {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = "Word Vim: Backspace / remove Word TAB",
    }
  )

  -- NORMAL MODE: delete a line together with its hidden
  -- Word TAB / paragraph-indent metadata.
  vim.keymap.set(
    "n",
    "dd",
    function()
      delete_current_lines(buf)
    end,
    {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = "Word Vim: delete line with paragraph metadata",
    }
  )

  -- NORMAL MODE: paragraph indent property.
  vim.keymap.set(
    "n",
    "<Tab>",
    function()
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1

      if not try_change_list_level(buf, row, 1) then
        M.change_paragraph_indent(buf, row, 1)
      end
    end,
    {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = "Word Vim: increase paragraph indent",
    }
  )

  vim.keymap.set(
    "n",
    "<S-Tab>",
    function()
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1

      if not try_change_list_level(buf, row, -1) then
        M.change_paragraph_indent(buf, row, -1)
      end
    end,
    {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = "Word Vim: decrease paragraph indent",
    }
  )
end

function M.setup()
end

return M
