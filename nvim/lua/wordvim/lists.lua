-- ============================================================
-- lua/wordvim/lists.lua
--
-- Four-level Word-style lists.
--
-- Ordered editor display:
--   1        Item
--   1.1      Item
--   1.1.1    Item
--   1.1.1.1  Item
--
-- Bullet editor display:
--   •  U+2022 / decimal 8226
--   ◦  U+25E6 / decimal 9702
--   ▪  U+25AA / decimal 9642
--   ▫  U+25AB / decimal 9643
--
-- DOCX bullet font: Courier New
--
-- Tab / Shift+Tab on a list item changes list level.
-- Maximum depth: 4.
-- ============================================================

local M = {}

local BULLETS = {
  "•", -- 8226
  "◦", -- 9702
  "▪", -- 9642
  "▫", -- 9643
}

local MAX_LEVEL = 4
local MARKDOWN_INDENT = 4

local function clamp_level(level)
  return math.max(1, math.min(MAX_LEVEL, tonumber(level) or 1))
end

local function count_leading_spaces(s)
  local prefix = tostring(s or ""):match("^(%s*)") or ""
  local expanded = prefix:gsub("\t", string.rep(" ", MARKDOWN_INDENT))
  return #expanded
end

local function markdown_level(indent)
  return clamp_level(math.floor(count_leading_spaces(indent) / MARKDOWN_INDENT) + 1)
end

local function ordered_label(level)
  local parts = {}
  for _ = 1, level do
    table.insert(parts, "1")
  end
  return table.concat(parts, ".")
end

local function bullet_level(symbol)
  for i, value in ipairs(BULLETS) do
    if symbol == value then
      return i
    end
  end
  return nil
end

local function parse_editor_ordered(line)
  local indent, label, body =
    tostring(line or ""):match("^(%s*)(%d[%d%.]*)%s+(.*)$")

  if not label then
    return nil
  end

  local level = 1
  for _ in label:gmatch("%.") do
    level = level + 1
  end

  if level > MAX_LEVEL then
    return nil
  end

  return {
    kind = "ordered",
    level = level,
    body = body,
    indent = indent,
  }
end

local function parse_editor_bullet(line)
  line = tostring(line or "")

  for level, symbol in ipairs(BULLETS) do
    local escaped = vim.pesc(symbol)

    local indent, body =
      line:match(
        "^(%s*)" .. escaped .. "%s+(.*)$"
      )

    if body then
      return {
        kind = "bullet",
        level = level,
        body = body,
        indent = indent,
      }
    end
  end

  return nil
end

local function parse_markdown_list(line)
  line = tostring(line or "")

  local indent, number, body =
    line:match("^(%s*)(%d+)[%.%)]%s+(.*)$")

  if number then
    return {
      kind = "ordered",
      level = markdown_level(indent),
      body = body,
      indent = indent,
    }
  end

  local bindent, marker, bbody =
    line:match("^(%s*)([-+*])%s+(.*)$")

  if marker then
    return {
      kind = "bullet",
      level = markdown_level(bindent),
      body = bbody,
      indent = bindent,
    }
  end

  return nil
end

function M.parse(line)
  return parse_editor_ordered(line)
    or parse_editor_bullet(line)
    or parse_markdown_list(line)
end

function M.is_list_line(line)
  return M.parse(line) ~= nil
end

local function editor_prefix(kind, level, label)
  level = clamp_level(level)

  local indent = string.rep(" ", (level - 1) * MARKDOWN_INDENT)

  if kind == "bullet" then
    return indent .. BULLETS[level] .. " "
  end

  return indent .. (label or ordered_label(level)) .. " "
end


-- Return the editor prefix for a list line. Used by paragraph handling to
-- continue a list when Enter is pressed at the end of an item.
function M.continuation_prefix(line)
  local item = M.parse(line)
  if not item then
    return nil, nil
  end

  if item.kind == "bullet" then
    return editor_prefix("bullet", item.level), item
  end

  return editor_prefix("ordered", item.level, ordered_label(item.level)), item
end

-- Explicitly leave list formatting on the current paragraph. This is useful
-- when the user wants to stop a list without relying on an empty list item.
function M.exit_current()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()
  local item = M.parse(line)

  if not item then
    vim.notify("Word Vim: current paragraph is not a list item", vim.log.levels.INFO)
    return false
  end

  vim.api.nvim_set_current_line(item.body or "")
  M.renumber_buffer(buf)

  local ok, word_styles = pcall(require, "wordvim.styles")
  if ok then
    word_styles.set_paragraph_style(buf, row, "Normal")
  end

  vim.bo[buf].modified = true
  return true
end


-- ------------------------------------------------------------
-- Convert Pandoc Markdown list markers into Word Vim display.
-- ------------------------------------------------------------

function M.to_editor_lines(lines)
  local result = {}
  local counters = { 0, 0, 0, 0 }
  local active_kind = nil

  for _, line in ipairs(lines or {}) do
    local item = parse_markdown_list(line)

    if not item then
      table.insert(result, line)
      active_kind = nil
      counters = { 0, 0, 0, 0 }

    elseif item.kind == "bullet" then
      local level = clamp_level(item.level)

      table.insert(
        result,
        editor_prefix("bullet", level) .. item.body
      )

      active_kind = "bullet"
      counters = { 0, 0, 0, 0 }

    else
      local level = clamp_level(item.level)

      if active_kind ~= "ordered" then
        counters = { 0, 0, 0, 0 }
      end

      for i = 1, level - 1 do
        if counters[i] == 0 then
          counters[i] = 1
        end
      end

      counters[level] = counters[level] + 1

      for i = level + 1, MAX_LEVEL do
        counters[i] = 0
      end

      local parts = {}
      for i = 1, level do
        table.insert(parts, tostring(counters[i]))
      end

      local label = table.concat(parts, ".")

      table.insert(
        result,
        editor_prefix("ordered", level, label) .. item.body
      )

      active_kind = "ordered"
    end
  end

  return result
end

-- ------------------------------------------------------------
-- Convert Word Vim editor display back to valid Pandoc Markdown.
-- ------------------------------------------------------------

function M.to_markdown_lines(lines)
  local result = {}

  for _, line in ipairs(lines or {}) do
    local item = parse_editor_ordered(line) or parse_editor_bullet(line)

    if not item then
      table.insert(result, line)
    else
      local indent = string.rep(" ", (item.level - 1) * MARKDOWN_INDENT)

      if item.kind == "bullet" then
        table.insert(result, indent .. "- " .. item.body)
      else
        -- Repeated "1." markers are intentional. Pandoc/Markdown
        -- will number the contiguous list automatically.
        table.insert(result, indent .. "1. " .. item.body)
      end
    end
  end

  return result
end

-- ------------------------------------------------------------
-- Recalculate hierarchical ordered labels after edits.
-- ------------------------------------------------------------

function M.renumber_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local counters = { 0, 0, 0, 0 }
  local active = false
  local changed = false

  for i, line in ipairs(lines) do
    local item = parse_editor_ordered(line)

    if item then
      local level = clamp_level(item.level)

      if not active then
        counters = { 0, 0, 0, 0 }
      end

      for n = 1, level - 1 do
        if counters[n] == 0 then
          counters[n] = 1
        end
      end

      counters[level] = counters[level] + 1

      for n = level + 1, MAX_LEVEL do
        counters[n] = 0
      end

      local parts = {}
      for n = 1, level do
        table.insert(parts, tostring(counters[n]))
      end

      local replacement =
        editor_prefix(
          "ordered",
          level,
          table.concat(parts, ".")
        ) .. item.body

      if replacement ~= line then
        lines[i] = replacement
        changed = true
      end

      active = true
    else
      if not parse_editor_bullet(line) then
        active = false
        counters = { 0, 0, 0, 0 }
      else
        active = false
        counters = { 0, 0, 0, 0 }
      end
    end
  end

  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

local function current_row_for_buf(buf)
  if vim.api.nvim_get_current_buf() ~= buf then
    return nil
  end
  return vim.api.nvim_win_get_cursor(0)[1] - 1
end

function M.change_level(buf, row, delta)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local line = vim.api.nvim_buf_get_lines(
    buf, row, row + 1, false
  )[1] or ""

  local item = parse_editor_ordered(line)
    or parse_editor_bullet(line)
    or parse_markdown_list(line)

  if not item then
    return false
  end

  local new_level = clamp_level(item.level + delta)

  if new_level == item.level then
    return true
  end

  local old_len = #line
  local replacement

  if item.kind == "bullet" then
    replacement =
      editor_prefix("bullet", new_level) .. item.body
  else
    replacement =
      editor_prefix(
        "ordered",
        new_level,
        ordered_label(new_level)
      ) .. item.body
  end

  vim.api.nvim_buf_set_lines(
    buf,
    row,
    row + 1,
    false,
    { replacement }
  )

  M.renumber_buffer(buf)

  vim.bo[buf].modified = true

  vim.notify(
    "Word Vim: list level -> " .. tostring(new_level),
    vim.log.levels.INFO
  )

  if current_row_for_buf(buf) == row then
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local delta_len = #replacement - old_len

    pcall(
      vim.api.nvim_win_set_cursor,
      0,
      {
        row + 1,
        math.max(0, col + delta_len),
      }
    )
  end

  return true
end

function M.toggle_current(kind)
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()

  local existing = parse_editor_ordered(line)
    or parse_editor_bullet(line)
    or parse_markdown_list(line)

  local body = line
  local level = 1

  if existing then
    body = existing.body
    level = existing.level

    if existing.kind == kind then
      vim.api.nvim_set_current_line(body)
      M.renumber_buffer(buf)
      return
    end
  end

  if kind == "bullet" then
    vim.api.nvim_set_current_line(
      editor_prefix("bullet", level) .. body
    )
  else
    vim.api.nvim_set_current_line(
      editor_prefix("ordered", level, ordered_label(level)) .. body
    )
    M.renumber_buffer(buf)
  end
end

local function convert_line_to_kind(line, kind, force_remove)
  local existing =
    parse_editor_ordered(line)
    or parse_editor_bullet(line)
    or parse_markdown_list(line)

  if vim.trim(line) == "" then
    return line
  end

  if force_remove then
    if existing then
      return existing.body
    end

    return line
  end

  local body = line
  local level = 1

  if existing then
    body = existing.body
    level = existing.level
  end

  if kind == "bullet" then
    return editor_prefix("bullet", level) .. body
  end

  return editor_prefix(
    "ordered",
    level,
    ordered_label(level)
  ) .. body
end

function M.toggle_range(kind, first_row, last_row)
  local buf = vim.api.nvim_get_current_buf()

  first_row = math.max(0, tonumber(first_row) or 0)
  last_row = math.max(first_row, tonumber(last_row) or first_row)

  local lines =
    vim.api.nvim_buf_get_lines(
      buf,
      first_row,
      last_row + 1,
      false
    )

  if #lines == 0 then
    return
  end

  -- Toggle rule for a selection:
  -- * if every nonblank selected row is already this list kind,
  --   remove the list from all selected rows;
  -- * otherwise apply the requested list kind to every nonblank row.
  local all_same_kind = true
  local found_nonblank = false

  for _, line in ipairs(lines) do
    if vim.trim(line) ~= "" then
      found_nonblank = true

      local item =
        parse_editor_ordered(line)
        or parse_editor_bullet(line)
        or parse_markdown_list(line)

      if not item or item.kind ~= kind then
        all_same_kind = false
        break
      end
    end
  end

  if not found_nonblank then
    return
  end

  local replacement = {}

  for _, line in ipairs(lines) do
    table.insert(
      replacement,
      convert_line_to_kind(
        line,
        kind,
        all_same_kind
      )
    )
  end

  vim.api.nvim_buf_set_lines(
    buf,
    first_row,
    last_row + 1,
    false,
    replacement
  )

  if kind == "ordered" and not all_same_kind then
    M.renumber_buffer(buf)
  elseif all_same_kind then
    M.renumber_buffer(buf)
  end

  vim.bo[buf].modified = true
end

function M.toggle_visual(kind)
  local cursor_row =
    vim.api.nvim_win_get_cursor(0)[1] - 1

  local anchor_row =
    vim.fn.line("v") - 1

  local first_row =
    math.min(cursor_row, anchor_row)

  local last_row =
    math.max(cursor_row, anchor_row)

  M.toggle_range(
    kind,
    first_row,
    last_row
  )
end

local function ps_escape_local(value)
  return tostring(value or ""):gsub("'", "''")
end

local function run_powershell_local(script)
  return require("wordvim.runtime").run_powershell(script)
end

function M.load_levels_from_docx(buf, docx)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local temp_docx =
    vim.fn.tempname() .. ".docx"

  local source_path =
    ps_escape_local(docx)

  local target_path =
    ps_escape_local(temp_docx)

  local copy_script = string.format([[
$source = '%s'
$target = '%s'

try {
    Copy-Item -LiteralPath $source -Destination $target -Force
}
catch {
    Write-Output $_.Exception.Message
    exit 1
}
]], source_path, target_path)

  local copied, copy_output =
    run_powershell_local(copy_script)

  if not copied then
    pcall(vim.fn.delete, temp_docx)
    return
  end

  local path =
    ps_escape_local(temp_docx)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

function Read-ZipText([string]$zipPath, [string]$entryName) {
    $zip = $null
    $reader = $null

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        $entry = $zip.GetEntry($entryName)

        if ($null -eq $entry) {
            return $null
        }

        $reader = New-Object System.IO.StreamReader(
            $entry.Open(),
            [System.Text.Encoding]::UTF8,
            $true
        )

        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }

        if ($null -ne $zip) {
            $zip.Dispose()
        }
    }
}

$documentText = Read-ZipText $path 'word/document.xml'
$numberingText = Read-ZipText $path 'word/numbering.xml'

if (($null -eq $documentText) -or ($null -eq $numberingText)) {
    exit 0
}

[xml]$document = $documentText
[xml]$numbering = $numberingText

$docNs = New-Object System.Xml.XmlNamespaceManager(
    $document.NameTable
)
$docNs.AddNamespace('w', $nsUri)

$numNs = New-Object System.Xml.XmlNamespaceManager(
    $numbering.NameTable
)
$numNs.AddNamespace('w', $nsUri)

function Get-ListKind([string]$numId) {
    $num = $numbering.SelectSingleNode(
        '/w:numbering/w:num[@w:numId="' + $numId + '"]',
        $numNs
    )

    if ($null -eq $num) {
        return $null
    }

    $absRef = $num.SelectSingleNode('w:abstractNumId', $numNs)

    if ($null -eq $absRef) {
        return $null
    }

    $absId = $absRef.GetAttribute('val', $nsUri)

    $abstract = $numbering.SelectSingleNode(
        '/w:numbering/w:abstractNum[@w:abstractNumId="' + $absId + '"]',
        $numNs
    )

    if ($null -eq $abstract) {
        return $null
    }

    $fmt = $abstract.SelectSingleNode('w:lvl[1]/w:numFmt', $numNs)

    if ($null -eq $fmt) {
        return $null
    }

    $value = $fmt.GetAttribute('val', $nsUri)

    if ($value -eq 'bullet') {
        return 'bullet'
    }

    if ($value -eq 'decimal') {
        return 'ordered'
    }

    return $null
}

$paragraphs = $document.SelectNodes(
    '/w:document/w:body/w:p[w:pPr/w:numPr/w:numId]',
    $docNs
)

foreach ($p in $paragraphs) {
    $numIdNode = $p.SelectSingleNode(
        'w:pPr/w:numPr/w:numId',
        $docNs
    )

    if ($null -eq $numIdNode) {
        continue
    }

    $numId = $numIdNode.GetAttribute('val', $nsUri)
    $kind = Get-ListKind $numId

    if ($null -eq $kind) {
        continue
    }

    $ilvlNode = $p.SelectSingleNode(
        'w:pPr/w:numPr/w:ilvl',
        $docNs
    )

    $level = 1

    if ($null -ne $ilvlNode) {
        $parsed = 0

        if (
          [int]::TryParse(
            $ilvlNode.GetAttribute('val', $nsUri),
            [ref]$parsed
          )
        ) {
            $level = $parsed + 1
        }
    }

    if ($level -lt 1) {
        $level = 1
    }

    if ($level -gt 4) {
        $level = 4
    }

    $parts = @()

    foreach ($t in $p.SelectNodes('.//w:t', $docNs)) {
        $parts += $t.InnerText
    }

    $text = ($parts -join '')

    $b64 = [Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes($text)
    )

    Write-Output ($kind + "`t" + $level + "`t" + $b64)
}
]], path)

  local ok, output =
    run_powershell_local(script)

  pcall(vim.fn.delete, temp_docx)

  if not ok or output == "" then
    return
  end

  local docx_items = {}

  for line in output:gmatch("[^\r\n]+") do
    local kind, level, b64 =
      line:match("^(.-)\t(.-)\t(.-)$")

    if kind and level and b64 then
      local decoded = ""

      local decode_ok, value =
        pcall(vim.base64.decode, b64)

      if decode_ok then
        decoded = value
      end

      table.insert(
        docx_items,
        {
          kind = kind,
          level = clamp_level(tonumber(level) or 1),
          text = vim.trim(decoded),
        }
      )
    end
  end

  if #docx_items == 0 then
    return
  end

  local lines =
    vim.api.nvim_buf_get_lines(
      buf,
      0,
      -1,
      false
    )

  local item_index = 1

  for row, line in ipairs(lines) do
    if item_index > #docx_items then
      break
    end

    local parsed =
      parse_editor_ordered(line)
      or parse_editor_bullet(line)
      or parse_markdown_list(line)

    if parsed then
      local item =
        docx_items[item_index]

      -- Consume by list kind + document order.  The DOCX is the
      -- authoritative source for level.
      if parsed.kind == item.kind then
        local body = parsed.body

        if item.kind == "bullet" then
          lines[row] =
            editor_prefix(
              "bullet",
              item.level
            ) .. body
        else
          lines[row] =
            editor_prefix(
              "ordered",
              item.level,
              ordered_label(item.level)
            ) .. body
        end

        item_index = item_index + 1
      end
    end
  end

  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    lines
  )

  M.renumber_buffer(buf)
end


function M.has_lists(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  for _, line in ipairs(
    vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  ) do
    if M.is_list_line(line) then
      return true
    end
  end

  return false
end

-- ------------------------------------------------------------
-- DOCX numbering.xml customization.
-- ------------------------------------------------------------

local function ps_escape(value)
  return tostring(value or ""):gsub("'", "''")
end

local function run_powershell(script)
  return require("wordvim.runtime").run_powershell(script)
end

local function normalize_docx_match_text(text)
  text = tostring(text or "")

  -- Strip Word Vim's editor-only list marker if present.
  local ordered =
    parse_editor_ordered(text)

  if ordered then
    text = ordered.body
  else
    local bullet =
      parse_editor_bullet(text)

    if bullet then
      text = bullet.body
    end
  end

  text = text:gsub("\\([\\`*_{}%[%]()#+%.!<>%-])", "%1")
  text = text:gsub("%*%*", "")
  text = text:gsub("__", "")
  text = text:gsub("~~", "")
  text = text:gsub("`", "")
  text = vim.trim(text)
  text = text:gsub("%s+", " ")

  return text
end

local function collect_list_save_specs(buf)
  local specs = {}
  local occurrences = {}

  local lines =
    vim.api.nvim_buf_get_lines(
      buf,
      0,
      -1,
      false
    )

  for _, line in ipairs(lines) do
    local item =
      parse_editor_ordered(line)
      or parse_editor_bullet(line)

    if item then
      local text =
        normalize_docx_match_text(item.body)

      if text ~= "" then
        local key =
          item.kind .. "\0" .. text

        occurrences[key] =
          (occurrences[key] or 0) + 1

        table.insert(
          specs,
          {
            kind = item.kind,
            level = clamp_level(item.level),
            text = text,
            occurrence = occurrences[key],
          }
        )
      end
    end
  end

  return specs
end


function M.apply_to_docx(docx, buf)
  local specs =
    collect_list_save_specs(buf)

  if #specs == 0 then
    return true
  end

  local temp_specs =
    vim.fn.tempname() .. ".tsv"

  local spec_lines = {}

  for _, spec in ipairs(specs) do
    table.insert(
      spec_lines,
      table.concat({
        spec.kind,
        tostring(spec.level),
        vim.base64.encode(spec.text),
        tostring(spec.occurrence),
      }, "\t")
    )
  end

  vim.fn.writefile(
    spec_lines,
    temp_specs
  )

  local path = ps_escape(docx)
  local specs_path = ps_escape(temp_specs)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$specsPath = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

function Read-ZipText([string]$zipPath, [string]$entryName) {
    $zip = $null
    $reader = $null

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        $entry = $zip.GetEntry($entryName)

        if ($null -eq $entry) {
            throw ($entryName + ' not found')
        }

        $reader = New-Object System.IO.StreamReader(
            $entry.Open(),
            [System.Text.Encoding]::UTF8,
            $true
        )

        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }

        if ($null -ne $zip) {
            $zip.Dispose()
        }
    }
}

function New-WElement($xml, [string]$local) {
    return $xml.CreateElement('w', $local, $nsUri)
}

function Set-WVal($node, [string]$value) {
    [void]$node.SetAttribute('val', $nsUri, $value)
}

function Serialize-Xml($xml) {
    # IMPORTANT:
    # Do not serialize through StringWriter.
    # StringWriter is UTF-16 internally and can emit an XML declaration
    # that disagrees with the UTF-8 bytes later written into the DOCX.
    # LibreOffice then reports a malformed XML declaration.
    #
    # XML declarations are optional in OOXML parts, so write only the
    # document element.  Its OuterXml is complete, valid XML and will be
    # encoded as UTF-8 by the StreamWriter below.
    return $xml.DocumentElement.OuterXml
}

# ------------------------------------------------------------
# Read Word Vim list specs in exact document order.
# ------------------------------------------------------------

$specs = @()

foreach (
    $line in
    (Get-Content -LiteralPath $specsPath -Encoding UTF8)
) {
    $fields = $line -split "`t"

    if ($fields.Count -lt 4) {
        continue
    }

    $text =
      [System.Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String(
          $fields[2]
        )
      )

    $specs += [PSCustomObject]@{
        Kind = $fields[0]
        Level = [int]$fields[1]
        Text = $text
        Occurrence = [int]$fields[3]
    }
}

$numberingText =
  Read-ZipText $path 'word/numbering.xml'

$documentText =
  Read-ZipText $path 'word/document.xml'

[xml]$numbering = $numberingText
[xml]$document = $documentText

$numberingNs =
  New-Object System.Xml.XmlNamespaceManager(
    $numbering.NameTable
  )
$numberingNs.AddNamespace('w', $nsUri)

$documentNs =
  New-Object System.Xml.XmlNamespaceManager(
    $document.NameTable
  )
$documentNs.AddNamespace('w', $nsUri)

# ------------------------------------------------------------
# Helpers to inspect Pandoc's existing list kind for a paragraph.
# ------------------------------------------------------------

function Get-ParagraphListKind($p) {
    $numIdNode =
      $p.SelectSingleNode(
        'w:pPr/w:numPr/w:numId',
        $documentNs
      )

    if ($null -eq $numIdNode) {
        return $null
    }

    $numId =
      $numIdNode.GetAttribute(
        'val',
        $nsUri
      )

    $num =
      $numbering.SelectSingleNode(
        '/w:numbering/w:num[@w:numId="' + $numId + '"]',
        $numberingNs
      )

    if ($null -eq $num) {
        return $null
    }

    $absRef =
      $num.SelectSingleNode(
        'w:abstractNumId',
        $numberingNs
      )

    if ($null -eq $absRef) {
        return $null
    }

    $absId =
      $absRef.GetAttribute(
        'val',
        $nsUri
      )

    $abstract =
      $numbering.SelectSingleNode(
        '/w:numbering/w:abstractNum[@w:abstractNumId="' + $absId + '"]',
        $numberingNs
      )

    if ($null -eq $abstract) {
        return $null
    }

    $fmt =
      $abstract.SelectSingleNode(
        'w:lvl[1]/w:numFmt',
        $numberingNs
      )

    if ($null -eq $fmt) {
        return $null
    }

    $value =
      $fmt.GetAttribute(
        'val',
        $nsUri
      )

    if ($value -eq 'bullet') {
        return 'bullet'
    }

    if ($value -eq 'decimal') {
        return 'ordered'
    }

    return $null
}

# ------------------------------------------------------------
# Allocate dedicated Word Vim numbering definitions.
# ------------------------------------------------------------

$maxAbstractId = 0

foreach (
    $abstract in
    $numbering.SelectNodes(
      '/w:numbering/w:abstractNum',
      $numberingNs
    )
) {
    $value = 0

    if (
      [int]::TryParse(
        $abstract.GetAttribute('abstractNumId', $nsUri),
        [ref]$value
      )
    ) {
        if ($value -gt $maxAbstractId) {
            $maxAbstractId = $value
        }
    }
}

$maxNumId = 0

foreach (
    $num in
    $numbering.SelectNodes(
      '/w:numbering/w:num',
      $numberingNs
    )
) {
    $value = 0

    if (
      [int]::TryParse(
        $num.GetAttribute('numId', $nsUri),
        [ref]$value
      )
    ) {
        if ($value -gt $maxNumId) {
            $maxNumId = $value
        }
    }
}

$bulletAbstractId = $maxAbstractId + 1
$orderedAbstractId = $maxAbstractId + 2
$bulletNumId = $maxNumId + 1
$orderedNumId = $maxNumId + 2

$root = $numbering.DocumentElement

function Add-AbstractNum(
    $xml,
    $root,
    [int]$abstractId,
    [string]$kind
) {
    $abstract = New-WElement $xml 'abstractNum'
    $abstract.SetAttribute(
        'abstractNumId',
        $nsUri,
        [string]$abstractId
    )

    $multi = New-WElement $xml 'multiLevelType'
    Set-WVal $multi 'multilevel'
    [void]$abstract.AppendChild($multi)

    $bulletChars = @(
        [string][char]8226,
        [string][char]9702,
        [string][char]9642,
        [string][char]9643
    )

    $orderedPatterns = @(
        '%%1',
        '%%1.%%2',
        '%%1.%%2.%%3',
        '%%1.%%2.%%3.%%4'
    )

    for ($level = 0; $level -lt 4; $level++) {
        $lvl = New-WElement $xml 'lvl'
        $lvl.SetAttribute(
            'ilvl',
            $nsUri,
            [string]$level
        )

        $startNode = New-WElement $xml 'start'
        Set-WVal $startNode '1'
        [void]$lvl.AppendChild($startNode)

        $numFmt = New-WElement $xml 'numFmt'
        $lvlText = New-WElement $xml 'lvlText'

        if ($kind -eq 'bullet') {
            Set-WVal $numFmt 'bullet'
            Set-WVal $lvlText $bulletChars[$level]
        }
        else {
            Set-WVal $numFmt 'decimal'
            Set-WVal $lvlText $orderedPatterns[$level]
        }

        [void]$lvl.AppendChild($numFmt)
        [void]$lvl.AppendChild($lvlText)

        $lvlJc = New-WElement $xml 'lvlJc'
        Set-WVal $lvlJc 'left'
        [void]$lvl.AppendChild($lvlJc)

        $pPr = New-WElement $xml 'pPr'
        $ind = New-WElement $xml 'ind'
        $left = 720 * ($level + 1)

        $ind.SetAttribute(
            'left',
            $nsUri,
            [string]$left
        )

        $ind.SetAttribute(
            'hanging',
            $nsUri,
            '360'
        )

        [void]$pPr.AppendChild($ind)
        [void]$lvl.AppendChild($pPr)

        if ($kind -eq 'bullet') {
            $rPr = New-WElement $xml 'rPr'
            $rFonts = New-WElement $xml 'rFonts'

            $rFonts.SetAttribute('ascii', $nsUri, 'Courier New')
            $rFonts.SetAttribute('hAnsi', $nsUri, 'Courier New')
            $rFonts.SetAttribute('eastAsia', $nsUri, 'Courier New')
            $rFonts.SetAttribute('cs', $nsUri, 'Courier New')

            [void]$rPr.AppendChild($rFonts)
            [void]$lvl.AppendChild($rPr)
        }

        [void]$abstract.AppendChild($lvl)
    }

    $firstNum =
      $root.SelectSingleNode(
        'w:num',
        $numberingNs
      )

    if ($null -ne $firstNum) {
        [void]$root.InsertBefore(
            $abstract,
            $firstNum
        )
    }
    else {
        [void]$root.AppendChild($abstract)
    }
}

function Add-Num(
    $xml,
    $root,
    [int]$numId,
    [int]$abstractId
) {
    $num = New-WElement $xml 'num'
    $num.SetAttribute(
        'numId',
        $nsUri,
        [string]$numId
    )

    $ref = New-WElement $xml 'abstractNumId'
    Set-WVal $ref ([string]$abstractId)

    [void]$num.AppendChild($ref)
    [void]$root.AppendChild($num)
}

Add-AbstractNum $numbering $root $bulletAbstractId 'bullet'
Add-AbstractNum $numbering $root $orderedAbstractId 'ordered'
Add-Num $numbering $root $bulletNumId $bulletAbstractId
Add-Num $numbering $root $orderedNumId $orderedAbstractId

# ------------------------------------------------------------
# IMPORTANT v3.8:
# Match Word Vim specs to Pandoc list paragraphs BY ORDER + KIND,
# not by exact text.
#
# Exact text matching was too fragile (Pandoc can split/normalize runs).
# That caused our new numbering definition to exist but list paragraphs
# to remain wired to Pandoc's old level-0 bullet definition, so
# LibreOffice still displayed the same dot on every level.
#
# We now:
#   1. collect only paragraphs that already have w:numPr
#   2. classify each as bullet/ordered from Pandoc numbering.xml
#   3. consume Word Vim specs in document order
#   4. explicitly write BOTH w:numId and w:ilvl
# ------------------------------------------------------------

$listParagraphs = @(
    $document.SelectNodes(
      '/w:document/w:body/w:p[w:pPr/w:numPr/w:numId]',
      $documentNs
    )
)

# Pandoc is free to use different numIds/abstract definitions for nested
# ordered lists.  Therefore its existing numId cannot be used as a stable
# indicator of whether a paragraph is "bullet" or "ordered".
#
# Word Vim already knows the exact logical list sequence before Pandoc
# runs.  The reliable invariant is document order:
#
#   Word Vim list item #1 -> Pandoc list paragraph #1
#   Word Vim list item #2 -> Pandoc list paragraph #2
#   ...
#
# We therefore rewire every Pandoc list paragraph from the Word Vim spec
# sequence and explicitly set BOTH numId and ilvl.
if ($listParagraphs.Count -ne $specs.Count) {
    $message = 'Pandoc list paragraph count mismatch. Word Vim expected ' + $specs.Count + ', Pandoc produced ' + $listParagraphs.Count
    throw $message
}

$wired = @()

for ($i = 0; $i -lt $specs.Count; $i++) {
    $spec = $specs[$i]
    $matched = $listParagraphs[$i]

    $pPr =
      $matched.SelectSingleNode(
        'w:pPr',
        $documentNs
      )

    if ($null -eq $pPr) {
        $pPr = New-WElement $document 'pPr'
        [void]$matched.PrependChild($pPr)
    }

    $numPr =
      $pPr.SelectSingleNode(
        'w:numPr',
        $documentNs
      )

    if ($null -eq $numPr) {
        $numPr = New-WElement $document 'numPr'
        [void]$pPr.AppendChild($numPr)
    }

    $ilvl =
      $numPr.SelectSingleNode(
        'w:ilvl',
        $documentNs
      )

    if ($null -eq $ilvl) {
        $ilvl = New-WElement $document 'ilvl'
        [void]$numPr.PrependChild($ilvl)
    }

    $numIdNode =
      $numPr.SelectSingleNode(
        'w:numId',
        $documentNs
      )

    if ($null -eq $numIdNode) {
        $numIdNode = New-WElement $document 'numId'
        [void]$numPr.AppendChild($numIdNode)
    }

    $level =
      [Math]::Max(
        0,
        [Math]::Min(
          3,
          [int]$spec.Level - 1
        )
      )

    $ilvl.SetAttribute(
        'val',
        $nsUri,
        [string]$level
    )

    if ($spec.Kind -eq 'bullet') {
        $expectedNumId = $bulletNumId
    }
    else {
        $expectedNumId = $orderedNumId
    }

    $numIdNode.SetAttribute(
        'val',
        $nsUri,
        [string]$expectedNumId
    )

    $wired += [PSCustomObject]@{
        Kind = $spec.Kind
        Level = $level
        NumId = $expectedNumId
    }
}

$newNumberingXml = Serialize-Xml $numbering
$newDocumentXml = Serialize-Xml $document

# ------------------------------------------------------------
# Replace only numbering.xml + document.xml.
# ------------------------------------------------------------

$fileStream = $null
$zipUpdate = $null
$numberingWriter = $null
$documentWriter = $null

try {
    $fileStream = [System.IO.File]::Open(
        $path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )

    $zipUpdate =
      New-Object System.IO.Compression.ZipArchive(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Update,
        $false
      )

    $oldNumbering =
      $zipUpdate.GetEntry(
        'word/numbering.xml'
      )

    $oldDocument =
      $zipUpdate.GetEntry(
        'word/document.xml'
      )

    if ($null -eq $oldNumbering) {
        throw 'word/numbering.xml not found during update'
    }

    if ($null -eq $oldDocument) {
        throw 'word/document.xml not found during update'
    }

    $oldNumbering.Delete()
    $oldDocument.Delete()

    $newNumbering =
      $zipUpdate.CreateEntry(
        'word/numbering.xml',
        [System.IO.Compression.CompressionLevel]::Optimal
      )

    $numberingWriter =
      New-Object System.IO.StreamWriter(
        $newNumbering.Open(),
        (New-Object System.Text.UTF8Encoding($false))
      )

    $numberingWriter.Write($newNumberingXml)
    $numberingWriter.Flush()
    $numberingWriter.Dispose()
    $numberingWriter = $null

    $newDocument =
      $zipUpdate.CreateEntry(
        'word/document.xml',
        [System.IO.Compression.CompressionLevel]::Optimal
      )

    $documentWriter =
      New-Object System.IO.StreamWriter(
        $newDocument.Open(),
        (New-Object System.Text.UTF8Encoding($false))
      )

    $documentWriter.Write($newDocumentXml)
    $documentWriter.Flush()
}
finally {
    if ($null -ne $numberingWriter) {
        $numberingWriter.Dispose()
    }

    if ($null -ne $documentWriter) {
        $documentWriter.Dispose()
    }

    if ($null -ne $zipUpdate) {
        $zipUpdate.Dispose()
    }

    if ($null -ne $fileStream) {
        $fileStream.Dispose()
    }
}

# ------------------------------------------------------------
# Strong validation:
# 1. exact symbols + Courier New exist in numbering.xml
# 2. every Word Vim list paragraph is really wired to expected
#    numId + ilvl in document.xml
# ------------------------------------------------------------

$checkNumberingText =
  Read-ZipText $path 'word/numbering.xml'

$checkDocumentText =
  Read-ZipText $path 'word/document.xml'

[xml]$checkNumbering = $checkNumberingText
[xml]$checkDocument = $checkDocumentText

$checkNs =
  New-Object System.Xml.XmlNamespaceManager(
    $checkNumbering.NameTable
  )
$checkNs.AddNamespace('w', $nsUri)

$checkDocNs =
  New-Object System.Xml.XmlNamespaceManager(
    $checkDocument.NameTable
  )
$checkDocNs.AddNamespace('w', $nsUri)

$checkAbstractPath = '/w:numbering/w:abstractNum[@w:abstractNumId="' + $bulletAbstractId + '"]'
$checkAbstract = $checkNumbering.SelectSingleNode($checkAbstractPath, $checkNs)

if ($null -eq $checkAbstract) {
    throw 'Word Vim bullet definition missing'
}

$expectedChars = @(
    [string][char]8226,
    [string][char]9702,
    [string][char]9642,
    [string][char]9643
)

for ($level = 0; $level -lt 4; $level++) {
    $levelPath = 'w:lvl[@w:ilvl="' + $level + '"]'
    $lvl = $checkAbstract.SelectSingleNode($levelPath, $checkNs)

    if ($null -eq $lvl) {
        throw ('Missing bullet level ' + $level)
    }

    $lvlText =
      $lvl.SelectSingleNode(
        'w:lvlText',
        $checkNs
      )

    $fonts =
      $lvl.SelectSingleNode(
        'w:rPr/w:rFonts',
        $checkNs
      )

    $actualBullet = $lvlText.GetAttribute('val', $nsUri)

    if ($actualBullet -ne $expectedChars[$level]) {
        throw ('Wrong bullet symbol at level ' + $level)
    }

    if ($null -eq $fonts) {
        throw ('Missing bullet font at level ' + $level)
    }

    $actualFont = $fonts.GetAttribute('ascii', $nsUri)

    if ($actualFont -ne 'Courier New') {
        throw ('Wrong bullet font at level ' + $level)
    }
}

$checkListParagraphs = @(
    $checkDocument.SelectNodes(
      '/w:document/w:body/w:p[w:pPr/w:numPr/w:numId]',
      $checkDocNs
    )
)

if ($checkListParagraphs.Count -ne $wired.Count) {
    $countMessage = 'List wiring validation count mismatch. Expected ' + $wired.Count + ', found ' + $checkListParagraphs.Count
    throw $countMessage
}

for ($i = 0; $i -lt $wired.Count; $i++) {
    $p = $checkListParagraphs[$i]

    $numIdNode =
      $p.SelectSingleNode(
        'w:pPr/w:numPr/w:numId',
        $checkDocNs
      )

    $ilvlNode =
      $p.SelectSingleNode(
        'w:pPr/w:numPr/w:ilvl',
        $checkDocNs
      )

    if ($null -eq $numIdNode) {
        throw ('List wiring validation: missing numId at item ' + ($i + 1))
    }

    if ($null -eq $ilvlNode) {
        throw ('List wiring validation: missing ilvl at item ' + ($i + 1))
    }

    $actualNumId = [int]$numIdNode.GetAttribute('val', $nsUri)
    $actualLevel = [int]$ilvlNode.GetAttribute('val', $nsUri)

    $numIdMismatch = $actualNumId -ne $wired[$i].NumId
    $levelMismatch = $actualLevel -ne $wired[$i].Level

    if ($numIdMismatch -or $levelMismatch) {
        throw ('List wiring validation failed at item ' + ($i + 1))
    }
}
]], path, specs_path)

  local ok, output =
    run_powershell(script)

  vim.fn.delete(temp_specs)

  if not ok then
    vim.notify(
      "Word Vim: could not configure multilevel lists:\n"
        .. output,
      vim.log.levels.ERROR
    )

    return false
  end

  return true
end

function M.setup()
  vim.api.nvim_create_user_command(
    "WordListNumbered",
    function()
      M.toggle_current("ordered")
    end,
    {
      desc = "Toggle four-level numbered list",
    }
  )

  vim.api.nvim_create_user_command(
    "WordListBullet",
    function()
      M.toggle_current("bullet")
    end,
    {
      desc = "Toggle four-level bullet list",
    }
  )

  vim.api.nvim_create_user_command(
    "WordListLevel",
    function(opts)
      local target = clamp_level(tonumber(opts.args))
      local buf = vim.api.nvim_get_current_buf()
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1
      local line = vim.api.nvim_get_current_line()
      local item = M.parse(line)

      if not item then
        vim.notify(
          "Word Vim: cursor is not on a list item",
          vim.log.levels.WARN
        )
        return
      end

      M.change_level(buf, row, target - item.level)
    end,
    {
      nargs = 1,
      desc = "Set list level 1-4",
    }
  )
end

return M
