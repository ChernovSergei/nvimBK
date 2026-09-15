-- ============================================================
-- lua/wordvim/pagebreaks.lua
--
-- Word Vim pages v4.6
--
-- 1. Manual page breaks are real DOCX <w:br w:type="page"/>.
-- 2. Automatic physical page boundaries are estimated from:
--      - paper size / orientation
--      - page margins
--      - paragraph Word style font size
--      - style spacing before / after
--      - wrapped text width on the physical page
--      - headings, lists, tables, code-like lines, images
-- 3. Automatic boundaries are virtual only and never saved as
--    explicit Word page breaks.
--
-- Statusline:
--   filename [+]   current/total   line:col   %
-- ============================================================

local M = {}

local manual_ns =
  vim.api.nvim_create_namespace("WordVimManualPageBreaks")

local auto_ns =
  vim.api.nvim_create_namespace("WordVimAutoPages")

local state = {}

local MARKER_PREFIX =
  "WORDVIM_PAGEBREAK_"

-- Written only into the disposable DOCX copy that Pandoc reads.  A real
-- break-only Word paragraph is otherwise discarded by Pandoc, forcing the
-- importer to guess its location from neighbouring text.  Keeping an exact
-- positional marker also works before empty paragraphs, tables and repeated
-- headings.
local READ_MARKER_PREFIX =
  "WORDVIM_READ_PAGEBREAK_7D4E91C2_"

local function get_state(buf)
  if not state[buf] then
    state[buf] = {
      manual_marks = {},
      auto_rows = {},
      auto_mark_ids = {},
      timer = nil,
    }
  end

  return state[buf]
end

local function ps_escape(value)
  return tostring(value or ""):gsub("'", "''")
end

local function run_powershell(script)
  return require("wordvim.runtime").run_powershell(script)
end

local function normalize_text(text)
  text = tostring(text or "")
  text = text:gsub("^%s*#+%s*", "")
  text = text:gsub("^%s*>+%s*", "")
  text = text:gsub("^%s*[-+*]%s+", "")
  text = text:gsub("^%s*%d+[%.%)]%s+", "")
  text = text:gsub("^%s*[%d%.]+%s+", "")
  text = text:gsub("^[•◦▪▫]%s+", "")
  text = text:gsub("\\([\\`*_{}%[%]()#+%.!<>%-])", "%1")
  text = text:gsub("%*%*", "")
  text = text:gsub("__", "")
  text = text:gsub("~~", "")
  text = text:gsub("`", "")
  text = vim.trim(text)
  text = text:gsub("%s+", " ")
  return text
end

local function display_width(text)
  local ok, width = pcall(vim.fn.strdisplaywidth, text or "")
  if ok then
    return width
  end
  return #(text or "")
end

local function delete_manual_row_mark(buf, row)
  local s = get_state(buf)

  local marks =
    vim.api.nvim_buf_get_extmarks(
      buf,
      manual_ns,
      { row, 0 },
      { row, -1 },
      {}
    )

  for _, mark in ipairs(marks) do
    s.manual_marks[mark[1]] = nil
    pcall(
      vim.api.nvim_buf_del_extmark,
      buf,
      manual_ns,
      mark[1]
    )
  end
end

function M.has_before(buf, row)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local marks =
    vim.api.nvim_buf_get_extmarks(
      buf,
      manual_ns,
      { row, 0 },
      { row, -1 },
      {}
    )

  for _, mark in ipairs(marks) do
    if get_state(buf).manual_marks[mark[1]] then
      return true
    end
  end

  return false
end

local function line_width(buf)
  local width = 72

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      width = math.max(
        24,
        vim.api.nvim_win_get_width(win) - 7
      )
      break
    end
  end

  return width
end

local function clear_auto_marks(buf)
  local s = get_state(buf)
  vim.api.nvim_buf_clear_namespace(buf, auto_ns, 0, -1)
  s.auto_mark_ids = {}
end

local function draw_auto_pages(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  clear_auto_marks(buf)

  vim.api.nvim_set_hl(
    0,
    "WordVimPageBoundary",
    {
      fg = "#6B7280",
    }
  )

  local width = line_width(buf)
  local s = get_state(buf)

  for _, row in ipairs(s.auto_rows) do
    if row > 0 and row < vim.api.nvim_buf_line_count(buf) then
      local id =
        vim.api.nvim_buf_set_extmark(
          buf,
          auto_ns,
          row,
          0,
          {
            right_gravity = false,
            virt_lines = {
              {
                {
                  string.rep("─", width),
                  "WordVimPageBoundary",
                },
              },
            },
            virt_lines_above = true,
          }
        )

      table.insert(s.auto_mark_ids, id)
    end
  end
end

function M.refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  draw_auto_pages(buf)
end

function M.set_before(buf, row, enabled, mark_modified)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  delete_manual_row_mark(buf, row)

  if enabled then
    local id =
      vim.api.nvim_buf_set_extmark(
        buf,
        manual_ns,
        row,
        0,
        {
          -- A manual page break belongs to the paragraph that follows it.
          -- If a new row is inserted immediately before that paragraph (O,
          -- paste, etc.), keep the break attached to the original paragraph.
          right_gravity = true,
        }
      )

    get_state(buf).manual_marks[id] = true
  end

  M.recalculate(buf)

  if mark_modified ~= false then
    vim.bo[buf].modified = true
  end

  pcall(vim.cmd, "redrawstatus")
end

function M.clear_range_metadata(buf, first_row, last_row)
  first_row = math.max(0, tonumber(first_row) or 0)
  last_row = math.max(first_row, tonumber(last_row) or first_row)

  for row = first_row, last_row do
    delete_manual_row_mark(buf, row)
  end

  M.recalculate(buf)
end

function M.toggle_current(enabled)
  local buf = vim.api.nvim_get_current_buf()

  if not vim.b[buf].docx_original_file then
    return
  end

  local row =
    vim.api.nvim_win_get_cursor(0)[1] - 1

  M.set_before(buf, row, enabled, true)
end

local function sorted_manual_rows(buf)
  local rows = {}
  local s = get_state(buf)

  local marks =
    vim.api.nvim_buf_get_extmarks(
      buf,
      manual_ns,
      0,
      -1,
      {}
    )

  for _, mark in ipairs(marks) do
    if s.manual_marks[mark[1]] then
      table.insert(rows, mark[2])
    end
  end

  table.sort(rows)
  return rows
end

local function style_for_row(buf, row)
  local ok_styles, styles =
    pcall(require, "wordvim.styles")

  if not ok_styles then
    return nil
  end

  local name =
    styles.get_effective_paragraph_style(buf, row)

  local style =
    styles.find_style(buf, name)

  if not style and name ~= "Normal" then
    style = styles.find_style(buf, "Normal")
  end

  return style, name
end

local function inherited_style(buf, style)
  local ok_styles, styles =
    pcall(require, "wordvim.styles")

  if not ok_styles then
    return style
  end

  local current = style
  local seen = {}

  while
    current
    and current.based_on
    and current.based_on ~= ""
    and not seen[current.based_on]
  do
    if
      current.size and current.size ~= ""
      and current.before and current.before ~= ""
      and current.after and current.after ~= ""
    then
      break
    end

    seen[current.based_on] = true
    local parent =
      styles.find_style(buf, current.based_on)

    if not parent then
      break
    end

    current = {
      size =
        (current.size and current.size ~= "")
        and current.size or parent.size,
      before =
        (current.before and current.before ~= "")
        and current.before or parent.before,
      after =
        (current.after and current.after ~= "")
        and current.after or parent.after,
      based_on = parent.based_on,
    }
  end

  return current
end

local function paragraph_metrics(buf, row, line, usable_width_pt)
  local ok_toc, toc =
    pcall(require, "wordvim.toc")

  if ok_toc then
    local toc_height =
      toc.estimated_height(buf, row)

    if toc_height then
      return toc_height
    end
  end

  local style, style_name =
    style_for_row(buf, row)

  style = inherited_style(buf, style or {})

  local font_pt = tonumber(style and style.size) or 11.0
  local before_pt = tonumber(style and style.before) or 0
  local after_pt = tonumber(style and style.after) or 0

  if style_name then
    local heading_level =
      tonumber(style_name:match("^Heading%s+(%d+)"))

    if heading_level then
      local fallback = {
        [1] = 20,
        [2] = 16,
        [3] = 14,
        [4] = 12,
        [5] = 11,
        [6] = 11,
      }
      if not tonumber(style and style.size) then
        font_pt = fallback[heading_level] or 11
      end
      if before_pt == 0 then
        before_pt = math.max(4, font_pt * 0.45)
      end
      if after_pt == 0 then
        after_pt = math.max(2, font_pt * 0.20)
      end
    end
  end

  local text = tostring(line or "")
  local trimmed = vim.trim(text)

  if trimmed == "" then
    return font_pt * 0.70
  end

  local indent_spaces =
    #(text:match("^(%s*)") or "")

  local list_indent_pt =
    math.floor(indent_spaces / 4) * 18

  local effective_width =
    math.max(72, usable_width_pt - list_indent_pt)

  -- Average proportional-font character width.
  -- Cyrillic and ASCII body text in Arial/Calibri/Aptos is normally
  -- near 0.50-0.56 em, so 0.53 is a useful page-layout estimate.
  local average_char_pt = math.max(4.2, font_pt * 0.53)

  local chars_per_line =
    math.max(8, effective_width / average_char_pt)

  local text_width = display_width(trimmed)
  local visual_lines =
    math.max(1, math.ceil(text_width / chars_per_line))

  -- Markdown table rows require extra vertical room in the exported DOCX.
  if trimmed:match("^|.*|$") then
    visual_lines = math.max(1, visual_lines)
    before_pt = before_pt + 2
    after_pt = after_pt + 2
  end

  -- Code / diagram-like lines tend to use fixed pitch and preserve
  -- horizontal structure.
  if
    trimmed:match("^```")
    or trimmed:match("^[│└├┌┐┘┬┴┼─]+")
    or trimmed:match("^%s*[%w_%.]+%s*=%s*")
  then
    visual_lines =
      math.max(
        visual_lines,
        math.ceil(text_width / math.max(8, effective_width / (font_pt * 0.60)))
      )
  end

  -- Images occupy real physical height even though the editor line is short.
  if trimmed:match("^!%[.-%]%(") then
    visual_lines = math.max(visual_lines, 12)
  end

  local line_height =
    font_pt * 1.20

  return before_pt
    + visual_lines * line_height
    + after_pt
end

local function page_geometry(buf)
  local ok_settings, pagesettings =
    pcall(require, "wordvim.pagesettings")

  if not ok_settings then
    return 451.0, 697.0
  end

  local dims =
    pagesettings.paper_dimensions(buf)

  if not dims then
    return 451.0, 697.0
  end

  local width_pt =
    (dims.width_cm - dims.left_cm - dims.right_cm)
    / 2.54 * 72

  local height_pt =
    (dims.height_cm - dims.top_cm - dims.bottom_cm)
    / 2.54 * 72

  return math.max(144, width_pt),
    math.max(144, height_pt)
end

function M.recalculate(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if not vim.b[buf].docx_original_file then
    return
  end

  local lines =
    vim.api.nvim_buf_get_lines(
      buf,
      0,
      -1,
      false
    )

  local usable_width_pt, usable_height_pt =
    page_geometry(buf)

  local manual = {}
  for _, row in ipairs(sorted_manual_rows(buf)) do
    manual[row] = true
  end

  local boundaries = {}
  local used = 0.0
  local page_start = 0

  for row, line in ipairs(lines) do
    local zero_row = row - 1

    if manual[zero_row] and zero_row > page_start then
      table.insert(boundaries, zero_row)
      used = 0.0
      page_start = zero_row
    end

    local height =
      paragraph_metrics(
        buf,
        zero_row,
        line,
        usable_width_pt
      )

    -- If this paragraph does not fit, start a new physical page before it.
    if
      used > 0
      and used + height > usable_height_pt
      and zero_row > page_start
    then
      -- Avoid duplicate boundary when a manual page break already starts here.
      if boundaries[#boundaries] ~= zero_row then
        table.insert(boundaries, zero_row)
      end

      used = 0.0
      page_start = zero_row
    end

    used = used + height
  end

  local s = get_state(buf)
  s.auto_rows = boundaries

  draw_auto_pages(buf)
  pcall(vim.cmd, "redrawstatus")

  -- PAGEREF preview depends on the current estimated physical page.
  local ok_crossrefs, crossrefs = pcall(require, "wordvim.crossrefs")
  if ok_crossrefs then
    crossrefs.refresh(buf)
  end
end

local function schedule_recalculate(buf)
  local s = get_state(buf)

  if s.timer then
    s.timer:stop()
    s.timer:close()
    s.timer = nil
  end

  local timer = vim.uv.new_timer()
  s.timer = timer

  timer:start(
    120,
    0,
    vim.schedule_wrap(function()
      if s.timer == timer then
        s.timer = nil
      end

      pcall(function()
        timer:stop()
        timer:close()
      end)

      if vim.api.nvim_buf_is_valid(buf) then
        M.recalculate(buf)
      end
    end)
  )
end

function M.page_info(buf, row)
  if not vim.api.nvim_buf_is_valid(buf) then
    return 1, 1
  end

  row = row or
    (vim.api.nvim_win_get_cursor(0)[1] - 1)

  local rows = get_state(buf).auto_rows
  local current = 1

  for _, break_row in ipairs(rows) do
    if break_row <= row then
      current = current + 1
    else
      break
    end
  end

  return current, #rows + 1
end

function M.statusline()
  local buf = vim.api.nvim_get_current_buf()

  if not vim.b[buf].docx_original_file then
    return ""
  end

  local row =
    vim.api.nvim_win_get_cursor(0)[1] - 1

  local current, total =
    M.page_info(buf, row)

  return tostring(current)
    .. "/"
    .. tostring(total)
end

function M.marker_for_row(row)
  return MARKER_PREFIX
    .. tostring(row + 1)
end

function M.read_marker_prefix()
  return READ_MARKER_PREFIX
end

local function restore_read_markers(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local marker_rows = {}

  for row, line in ipairs(lines) do
    if vim.trim(line or ""):match(
      "^" .. READ_MARKER_PREFIX .. "%d+$"
    ) then
      marker_rows[#marker_rows + 1] = row - 1
    end
  end

  if #marker_rows == 0 then
    return false
  end

  -- Delete bottom-up so each stored source row stays valid.  Neovim moves
  -- paragraph/table/style extmarks together with the remaining lines.
  for i = #marker_rows, 1, -1 do
    vim.api.nvim_buf_set_lines(
      buf,
      marker_rows[i],
      marker_rows[i] + 1,
      false,
      {}
    )
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local already_removed = 0

  for _, source_row in ipairs(marker_rows) do
    local target_row = source_row - already_removed
    target_row = math.max(0, math.min(target_row, line_count - 1))

    local id = vim.api.nvim_buf_set_extmark(
      buf,
      manual_ns,
      target_row,
      0,
      { right_gravity = true }
    )

    get_state(buf).manual_marks[id] = true
    already_removed = already_removed + 1
  end

  return true
end

function M.load_from_docx(buf, docx)
  state[buf] = {
    manual_marks = {},
    auto_rows = {},
    auto_mark_ids = {},
    timer = nil,
  }

  vim.api.nvim_buf_clear_namespace(
    buf,
    manual_ns,
    0,
    -1
  )

  vim.api.nvim_buf_clear_namespace(
    buf,
    auto_ns,
    0,
    -1
  )

  -- v6.58 read copies carry exact break positions through Pandoc.  Prefer
  -- those markers over the older text-matching fallback below.
  if restore_read_markers(buf) then
    M.recalculate(buf)
    vim.bo[buf].modified = false
    return
  end

  local temp =
    vim.fn.tempname() .. ".docx"

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
]],
    ps_escape(docx),
    ps_escape(temp)
  )

  local copied =
    run_powershell(copy_script)

  if not copied then
    pcall(vim.fn.delete, temp)
    M.recalculate(buf)
    return
  end

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

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

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $pendingBreak = $false

    foreach ($p in $xml.SelectNodes('/w:document/w:body/w:p', $ns)) {
        $hasPageBreak = $false

        foreach ($br in $p.SelectNodes('.//w:br', $ns)) {
            if ($br.GetAttribute('type', $nsUri) -eq 'page') {
                $hasPageBreak = $true
                break
            }
        }

        $parts = @()

        foreach ($t in $p.SelectNodes('.//w:t', $ns)) {
            $parts += $t.InnerText
        }

        $text = ($parts -join '')

        if ($hasPageBreak) {
            $pendingBreak = $true
        }

        if (
          $pendingBreak
          -and
          -not [string]::IsNullOrWhiteSpace($text)
        ) {
            $b64 = [Convert]::ToBase64String(
                [System.Text.Encoding]::UTF8.GetBytes($text)
            )

            Write-Output $b64
            $pendingBreak = $false
        }
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
]], ps_escape(temp))

  local ok, output =
    run_powershell(script)

  pcall(vim.fn.delete, temp)

  if ok and output ~= "" then
    local wanted = {}

    for line in output:gmatch("[^\r\n]+") do
      local ok_decode, value =
        pcall(vim.base64.decode, line)

      if ok_decode then
        table.insert(
          wanted,
          normalize_text(value)
        )
      end
    end

    local lines =
      vim.api.nvim_buf_get_lines(
        buf,
        0,
        -1,
        false
      )

    local search_row = 1

    for _, target in ipairs(wanted) do
      for i = search_row, #lines do
        if normalize_text(lines[i]) == target then
          local id =
            vim.api.nvim_buf_set_extmark(
              buf,
              manual_ns,
              i - 1,
              0,
              {
                -- Restored page-break metadata follows the paragraph it
                -- precedes when rows are inserted at this boundary.
                right_gravity = true,
              }
            )

          get_state(buf).manual_marks[id] = true
          search_row = i + 1
          break
        end
      end
    end
  end

  M.recalculate(buf)
  vim.bo[buf].modified = false
end

function M.apply_to_docx(docx)
  local path = ps_escape(docx)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$prefix = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

function Find-DocEntry($zip) {
    $entry = $zip.GetEntry('word/document.xml')
    if ($null -ne $entry) { return $entry }

    # Be tolerant of malformed/legacy OPC packages that contain Windows
    # backslashes in ZIP entry names.  Normalize only for comparison; the
    # update phase below rewrites document.xml using the canonical '/' name.
    foreach ($candidate in @($zip.Entries)) {
        $normalized = ([string]$candidate.FullName) -replace '\\', '/'
        if ($normalized.TrimStart('/') -ieq 'word/document.xml') {
            return $candidate
        }
    }

    return $null
}

$zipRead = $null
$reader = $null

try {
    $zipRead = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = Find-DocEntry $zipRead

    if ($null -eq $entry) {
        $names = (@($zipRead.Entries) | ForEach-Object { $_.FullName }) -join ', '
        throw ('word/document.xml not found. ZIP entries: ' + $names)
    }

    $reader = New-Object System.IO.StreamReader(
        $entry.Open(),
        [System.Text.Encoding]::UTF8,
        $true
    )

    [xml]$xml = $reader.ReadToEnd()
}
finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }

    if ($null -ne $zipRead) {
        $zipRead.Dispose()
    }
}

$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('w', $nsUri)

$paragraphs = @(
    $xml.SelectNodes('/w:document/w:body/w:p', $ns)
)

foreach ($p in $paragraphs) {
    $parts = @()

    foreach ($t in $p.SelectNodes('.//w:t', $ns)) {
        $parts += $t.InnerText
    }

    $text = ($parts -join '')

    if (-not $text.StartsWith($prefix)) {
        continue
    }

    foreach ($child in @($p.ChildNodes)) {
        if ($child.LocalName -ne 'pPr') {
            [void]$p.RemoveChild($child)
        }
    }

    $run = $xml.CreateElement('w', 'r', $nsUri)
    $br = $xml.CreateElement('w', 'br', $nsUri)
    [void]$br.SetAttribute('type', $nsUri, 'page')

    [void]$run.AppendChild($br)
    [void]$p.AppendChild($run)
}

$newXml = $xml.DocumentElement.OuterXml

$fileStream = $null
$zipUpdate = $null
$writer = $null

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

    $oldEntry = Find-DocEntry $zipUpdate
    if ($null -eq $oldEntry) {
        throw 'word/document.xml not found during page-break ZIP update'
    }
    $oldEntry.Delete()

    # Always recreate with the canonical OPC path separator.
    $newEntry = $zipUpdate.CreateEntry(
        'word/document.xml',
        [System.IO.Compression.CompressionLevel]::Optimal
    )

    $writer = New-Object System.IO.StreamWriter(
        $newEntry.Open(),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $writer.Write($newXml)
    $writer.Flush()
}
finally {
    if ($null -ne $writer) {
        $writer.Dispose()
    }

    if ($null -ne $zipUpdate) {
        $zipUpdate.Dispose()
    }

    if ($null -ne $fileStream) {
        $fileStream.Dispose()
    }
}

$zipCheck = $null
$checkReader = $null

try {
    $zipCheck = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = Find-DocEntry $zipCheck
    if ($null -eq $entry) {
        throw 'word/document.xml not found after page-break update'
    }

    $checkReader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$checkXml = $checkReader.ReadToEnd()

    if ($null -eq $checkXml.DocumentElement) {
        throw 'Invalid document.xml after page-break update'
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
]],
    path,
    MARKER_PREFIX
  )

  local ok, output =
    run_powershell(script)

  if not ok then
    vim.notify(
      "Word Vim: could not write page breaks:\n"
        .. output,
      vim.log.levels.ERROR
    )

    return false
  end

  return true
end

function M.attach(buf)
  vim.keymap.set(
    "n",
    "<leader>pb",
    function()
      M.toggle_current(true)
    end,
    {
      buffer = buf,
      silent = true,
      desc = "Word Vim: insert page break",
    }
  )

  vim.keymap.set(
    "n",
    "<leader>pd",
    function()
      M.toggle_current(false)
    end,
    {
      buffer = buf,
      silent = true,
      desc = "Word Vim: delete page break",
    }
  )
end

function M.detach(buf)
  local s = state[buf]

  if s and s.timer then
    pcall(function()
      s.timer:stop()
      s.timer:close()
    end)
  end

  state[buf] = nil
end

function M.setup()
  _G.WordVimPageStatus = function()
    return M.statusline()
  end

  vim.api.nvim_create_user_command(
    "WordPageBreak",
    function()
      M.toggle_current(true)
    end,
    {
      desc = "Insert page break before current paragraph",
    }
  )

  vim.api.nvim_create_user_command(
    "WordPageBreakDelete",
    function()
      M.toggle_current(false)
    end,
    {
      desc = "Delete page break before current paragraph",
    }
  )

  vim.api.nvim_create_user_command(
    "WordPageRecalculate",
    function()
      M.recalculate(vim.api.nvim_get_current_buf())
    end,
    {
      desc = "Recalculate Word Vim physical page boundaries",
    }
  )

  vim.api.nvim_create_autocmd(
    {
      "CursorMoved",
      "CursorMovedI",
    },
    {
      callback = function(args)
        if vim.b[args.buf].docx_original_file then
          pcall(vim.cmd, "redrawstatus")
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    {
      "TextChanged",
      "TextChangedI",
      "TextChangedP",
    },
    {
      callback = function(args)
        if vim.b[args.buf].docx_original_file then
          schedule_recalculate(args.buf)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "User",
    {
      pattern = "WordVimStyleChanged",
      callback = function(args)
        local buf =
          (args.data and args.data.buf)
          or vim.api.nvim_get_current_buf()

        if vim.api.nvim_buf_is_valid(buf) then
          schedule_recalculate(buf)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "WinResized",
    {
      callback = function()
        local buf =
          vim.api.nvim_get_current_buf()

        if vim.b[buf].docx_original_file then
          M.refresh(buf)
        end
      end,
    }
  )
end

return M
