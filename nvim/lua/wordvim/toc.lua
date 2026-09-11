-- ============================================================
-- lua/wordvim/toc.lua
--
-- Word Vim Table of Contents
--
-- Normal mode:
--   Space t c       insert TOC before current paragraph
--   Space t d       delete TOC
--
-- Commands:
--   :WordTOC
--   :WordTOCDelete
--   :WordTOCRefresh
--
-- Editor:
--   The title "Содержание" is a real editor row.
--   TOC entries are virtual lines generated from Heading 1..3.
--
-- DOCX:
--   The editor TOC is saved as a genuine Word TOC field:
--
--       TOC \o "1-3" \h \z \u
--
--   A visible field result is generated immediately so Word /
--   ONLYOFFICE can display the contents even before field refresh.
-- ============================================================

local M = {}

local ns =
  vim.api.nvim_create_namespace("WordVimTOC")

local state = {}
local pending_open = {}

local MARKER_PREFIX = "WORDVIM_TOC_"
local DEFAULT_TITLE = "Table of context"
local MAX_LEVEL = 3

local function get_state(buf)
  if not state[buf] then
    state[buf] = {
      anchor_id = nil,
      timer = nil,
      outline_buf = nil,
      outline_win = nil,
      outline_rows = {},
      source_win = nil,
    }
  end
  return state[buf]
end

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

local function clean_heading_text(line)
  local text = tostring(line or "")
  text = text:gsub("^%s*#+%s*", "")
  text = text:gsub("^%s*[%d%.]+%s+", "")
  text = text:gsub("^%s*[•◦▪▫]%s+", "")
  text = text:gsub("%*%*", "")
  text = text:gsub("__", "")
  text = text:gsub("~~", "")
  text = text:gsub("`", "")
  return vim.trim(text)
end

local function anchor_row(buf)
  local s = get_state(buf)

  if not s.anchor_id then
    return nil
  end

  local ok, pos =
    pcall(
      vim.api.nvim_buf_get_extmark_by_id,
      buf,
      ns,
      s.anchor_id,
      {}
    )

  if not ok or not pos or #pos < 2 then
    s.anchor_id = nil
    return nil
  end

  return pos[1]
end

function M.has_toc(buf)
  return anchor_row(buf) ~= nil
end

function M.has_anchor(buf, row)
  return anchor_row(buf) == row
end

function M.marker_for_row(row)
  return MARKER_PREFIX .. tostring(row + 1)
end

local function heading_level(buf, row)
  local ok_styles, styles =
    pcall(require, "wordvim.styles")

  if not ok_styles then
    return nil
  end

  local style =
    styles.get_effective_paragraph_style(buf, row)

  if not style then
    return nil
  end

  local level =
    tonumber(tostring(style):match("^Heading%s+(%d+)$"))

  if level and level >= 1 and level <= MAX_LEVEL then
    return level
  end

  return nil
end

function M.entries(buf)
  local result = {}

  if not vim.api.nvim_buf_is_valid(buf) then
    return result
  end

  local lines =
    vim.api.nvim_buf_get_lines(
      buf,
      0,
      -1,
      false
    )

  local ok_pages, pagebreaks =
    pcall(require, "wordvim.pagebreaks")

  for i, line in ipairs(lines) do
    local row = i - 1
    local level = heading_level(buf, row)

    if level then
      local title = clean_heading_text(line)

      if title ~= "" then
        local page = 1

        if ok_pages then
          page = select(
            1,
            pagebreaks.page_info(buf, row)
          )
        end

        table.insert(result, {
          row = row,
          level = level,
          title = title,
          page = page,
        })
      end
    end
  end

  return result
end

local function display_width(text)
  local ok, width =
    pcall(vim.fn.strdisplaywidth, text or "")

  if ok then
    return width
  end

  return #(text or "")
end

local function preview_width(buf)
  local width = 72

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      width = math.max(
        36,
        vim.api.nvim_win_get_width(win) - 8
      )
      break
    end
  end

  return width
end

local function build_preview_line(entry, width)
  local indent =
    string.rep("  ", math.max(0, entry.level - 1))

  local left =
    indent .. entry.title

  local page =
    tostring(entry.page or 1)

  local dots =
    math.max(
      3,
      width - display_width(left) - display_width(page) - 1
    )

  return left
    .. " "
    .. string.rep(".", dots)
    .. " "
    .. page
end

function M.refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local row = anchor_row(buf)

  if row == nil then
    return
  end

  local s = get_state(buf)
  local width = preview_width(buf)
  local virt_lines = {}

  vim.api.nvim_set_hl(
    0,
    "WordVimTOCEntry",
    {
      fg = "#9CA3AF",
    }
  )

  local entries = M.entries(buf)

  if #entries == 0 then
    table.insert(
      virt_lines,
      {
        {
          "  Нет заголовков Heading 1–3",
          "WordVimTOCEntry",
        },
      }
    )
  else
    for _, entry in ipairs(entries) do
      table.insert(
        virt_lines,
        {
          {
            build_preview_line(entry, width),
            "WordVimTOCEntry",
          },
        }
      )
    end
  end

  pcall(
    vim.api.nvim_buf_set_extmark,
    buf,
    ns,
    row,
    0,
    {
      id = s.anchor_id,
      right_gravity = true,
      virt_lines = virt_lines,
      virt_lines_above = false,
    }
  )
end

local function set_anchor(buf, row)
  -- Keep the TOC extmark attached to the title paragraph itself.
  -- With right_gravity=false, Normal-mode O inserts a new line at the
  -- same boundary and the extmark stays above the insertion, while the
  -- real title moves down. The virtual TOC then appears detached from
  -- its title. right_gravity=true makes the anchor follow the original
  -- title paragraph, so title + virtual TOC move as one visual block.
  local s = get_state(buf)

  if s.anchor_id then
    pcall(
      vim.api.nvim_buf_del_extmark,
      buf,
      ns,
      s.anchor_id
    )
  end

  s.anchor_id =
    vim.api.nvim_buf_set_extmark(
      buf,
      ns,
      row,
      0,
      {
        right_gravity = true,
      }
    )

  M.refresh(buf)
end

local function schedule_refresh(buf)
  local s = get_state(buf)

  if s.timer then
    pcall(function()
      s.timer:stop()
      s.timer:close()
    end)
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

      if
        vim.api.nvim_buf_is_valid(buf)
        and M.has_toc(buf)
      then
        M.refresh(buf)
        M.refresh_outline(buf)
      end
    end)
  )
end

function M.insert()
  local buf =
    vim.api.nvim_get_current_buf()

  if not vim.b[buf].docx_original_file then
    vim.notify(
      "Word Vim: TOC is available for DOCX buffers",
      vim.log.levels.WARN
    )
    return
  end

  if M.has_toc(buf) then
    vim.notify(
      "Word Vim: this document already has a Table of Contents",
      vim.log.levels.WARN
    )
    return
  end

  local row =
    vim.api.nvim_win_get_cursor(0)[1] - 1

  vim.api.nvim_buf_set_lines(
    buf,
    row,
    row,
    false,
    { DEFAULT_TITLE }
  )

  set_anchor(buf, row)

  local ok_styles, styles =
    pcall(require, "wordvim.styles")

  if ok_styles then
    local toc_style =
      styles.find_style(buf, "TOC Heading")
      or styles.find_style(buf, "TOCHeading")

    if toc_style then
      styles.set_paragraph_style(
        buf,
        row,
        toc_style.name
      )
    end
  end

  vim.bo[buf].modified = true

  local ok_pages, pagebreaks =
    pcall(require, "wordvim.pagebreaks")

  if ok_pages then
    pagebreaks.recalculate(buf)
  end

  vim.api.nvim_win_set_cursor(
    0,
    { row + 1, 0 }
  )
end

function M.delete()
  local buf =
    vim.api.nvim_get_current_buf()

  local row = anchor_row(buf)

  if row == nil then
    vim.notify(
      "Word Vim: this document has no Table of Contents",
      vim.log.levels.WARN
    )
    return
  end

  local s = get_state(buf)

  pcall(
    vim.api.nvim_buf_del_extmark,
    buf,
    ns,
    s.anchor_id
  )

  s.anchor_id = nil

  if row < vim.api.nvim_buf_line_count(buf) then
    vim.api.nvim_buf_set_lines(
      buf,
      row,
      row + 1,
      false,
      {}
    )
  end

  vim.bo[buf].modified = true

  local ok_pages, pagebreaks =
    pcall(require, "wordvim.pagebreaks")

  if ok_pages then
    pagebreaks.recalculate(buf)
  end
end

function M.estimated_height(buf, row)
  if not M.has_anchor(buf, row) then
    return nil
  end

  local entries = M.entries(buf)

  -- Title + one line per TOC entry.
  -- TOC levels are normally 10–11 pt with compact spacing.
  return 24 + math.max(1, #entries) * 14
end

-- ------------------------------------------------------------
-- TOC / heading navigation window
-- ------------------------------------------------------------

local function close_outline(buf)
  local s = get_state(buf)

  if s.outline_win and vim.api.nvim_win_is_valid(s.outline_win) then
    pcall(vim.api.nvim_win_close, s.outline_win, true)
  end

  if s.outline_buf and vim.api.nvim_buf_is_valid(s.outline_buf) then
    pcall(vim.api.nvim_buf_delete, s.outline_buf, { force = true })
  end

  s.outline_win = nil
  s.outline_buf = nil
  s.outline_rows = {}
  s.source_win = nil
end

local function outline_entry_text(entry)
  local prefix = string.rep("  ", math.max(0, entry.level - 1))

  return prefix .. entry.title
end

function M.refresh_outline(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local s = get_state(buf)

  if
    not s.outline_buf
    or not vim.api.nvim_buf_is_valid(s.outline_buf)
  then
    return
  end

  local entries = M.entries(buf)
  local lines = {}
  local rows = {}

  if #entries == 0 then
    lines = { "No Heading 1-3 found" }
  else
    for _, entry in ipairs(entries) do
      table.insert(lines, outline_entry_text(entry))
      table.insert(rows, entry)
    end
  end

  vim.bo[s.outline_buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    s.outline_buf,
    0,
    -1,
    false,
    lines
  )
  vim.bo[s.outline_buf].modifiable = false

  s.outline_rows = rows
end

local function jump_from_outline(source_buf)
  local s = get_state(source_buf)

  if
    not s.outline_win
    or not vim.api.nvim_win_is_valid(s.outline_win)
  then
    return
  end

  local outline_row =
    vim.api.nvim_win_get_cursor(s.outline_win)[1]

  local entry =
    s.outline_rows[outline_row]

  if not entry then
    return
  end

  local target_win = s.source_win

  if
    not target_win
    or not vim.api.nvim_win_is_valid(target_win)
    or vim.api.nvim_win_get_buf(target_win) ~= source_buf
  then
    for _, win in ipairs(vim.fn.win_findbuf(source_buf)) do
      if
        vim.api.nvim_win_is_valid(win)
        and win ~= s.outline_win
      then
        target_win = win
        break
      end
    end
  end

  if not target_win or not vim.api.nvim_win_is_valid(target_win) then
    return
  end

  vim.api.nvim_set_current_win(target_win)

  local line_count =
    vim.api.nvim_buf_line_count(source_buf)

  local target_row =
    math.max(
      0,
      math.min(entry.row, line_count - 1)
    )

  vim.api.nvim_win_set_cursor(
    target_win,
    { target_row + 1, 0 }
  )

  vim.cmd("normal! zz")

  -- Selection is complete: close the contents window.
  close_outline(source_buf)
end

function M.open_outline()
  local source_buf =
    vim.api.nvim_get_current_buf()

  if not vim.b[source_buf].docx_original_file then
    vim.notify(
      "Word Vim: contents window is available for DOCX buffers",
      vim.log.levels.WARN
    )
    return
  end

  local s = get_state(source_buf)

  if
    s.outline_win
    and vim.api.nvim_win_is_valid(s.outline_win)
  then
    vim.api.nvim_set_current_win(s.outline_win)
    return
  end

  s.source_win =
    vim.api.nvim_get_current_win()

  local outline_buf =
    vim.api.nvim_create_buf(false, true)

  vim.bo[outline_buf].buftype = "nofile"
  vim.bo[outline_buf].bufhidden = "wipe"
  vim.bo[outline_buf].swapfile = false
  vim.bo[outline_buf].modifiable = true
  vim.bo[outline_buf].filetype = "wordvim-toc"

  -- Open as a centered floating navigation window.
  local width =
    math.max(
      40,
      math.min(72, vim.o.columns - 10)
    )

  local max_height =
    math.max(
      8,
      vim.o.lines - 8
    )

  local entry_count =
    math.max(
      1,
      #M.entries(source_buf)
    )

  local height =
    math.max(
      8,
      math.min(max_height, entry_count + 2)
    )

  local row =
    math.max(
      1,
      math.floor((vim.o.lines - height) / 2 - 1)
    )

  local col =
    math.max(
      1,
      math.floor((vim.o.columns - width) / 2)
    )

  local outline_win =
    vim.api.nvim_open_win(
      outline_buf,
      true,
      {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Contents ",
        title_pos = "center",
      }
    )

  vim.wo[outline_win].number = false
  vim.wo[outline_win].relativenumber = false
  vim.wo[outline_win].wrap = false
  vim.wo[outline_win].cursorline = true
  vim.wo[outline_win].signcolumn = "no"
  vim.wo[outline_win].foldcolumn = "0"

  s.outline_buf = outline_buf
  s.outline_win = outline_win

  M.refresh_outline(source_buf)

  vim.keymap.set(
    "n",
    "<CR>",
    function()
      jump_from_outline(source_buf)
    end,
    {
      buffer = outline_buf,
      silent = true,
      desc = "Word Vim: jump to heading",
    }
  )

  vim.keymap.set(
    "n",
    "e",
    function()
      jump_from_outline(source_buf)
    end,
    {
      buffer = outline_buf,
      silent = true,
      desc = "Word Vim: jump to heading",
    }
  )

  vim.keymap.set(
    "n",
    "q",
    function()
      close_outline(source_buf)
    end,
    {
      buffer = outline_buf,
      silent = true,
      desc = "Word Vim: close contents window",
    }
  )

  vim.keymap.set(
    "n",
    "<Esc>",
    function()
      close_outline(source_buf)
    end,
    {
      buffer = outline_buf,
      silent = true,
      desc = "Word Vim: close contents window",
    }
  )
end

function M.toggle_outline()
  local buf =
    vim.api.nvim_get_current_buf()

  if not vim.b[buf].docx_original_file then
    return
  end

  local s = get_state(buf)

  if
    s.outline_win
    and vim.api.nvim_win_is_valid(s.outline_win)
  then
    close_outline(buf)
  else
    M.open_outline()
  end
end

-- ------------------------------------------------------------
-- Existing DOCX TOC detection
-- ------------------------------------------------------------

local function inspect_docx_toc(docx)
  local temp = vim.fn.tempname() .. ".docx"

  local copied = vim.uv.fs_copyfile(docx, temp)

  if not copied then
    return nil
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

    $paragraphs = @(
        $xml.SelectNodes('/w:document/w:body/w:p', $ns)
    )

    $tocIndex = -1

    for ($i = 0; $i -lt $paragraphs.Count; $i++) {
        $instr = ''
        foreach ($node in $paragraphs[$i].SelectNodes('.//w:instrText', $ns)) {
            $instr += $node.InnerText
        }

        if ($instr -match '(^|\s)TOC(\s|$)') {
            $tocIndex = $i
            break
        }
    }

    if ($tocIndex -lt 0) {
        exit 0
    }

    $titleIndex = $tocIndex - 1

    if ($titleIndex -lt 0) {
        $titleIndex = $tocIndex
    }

    $titleParts = @()
    foreach ($t in $paragraphs[$titleIndex].SelectNodes('.//w:t', $ns)) {
        $titleParts += $t.InnerText
    }

    $title = ($titleParts -join '')
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = 'Содержание'
    }

    $titleB64 = [Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes($title)
    )

    Write-Output ('TITLE' + "`t" + $titleB64)

    $insideResult = $false

    for ($i = $tocIndex; $i -lt $paragraphs.Count; $i++) {
        $p = $paragraphs[$i]

        foreach ($fld in $p.SelectNodes('.//w:fldChar', $ns)) {
            $kind = $fld.GetAttribute('fldCharType', $nsUri)

            if ($kind -eq 'separate') {
                $insideResult = $true
            }
        }

        if ($insideResult) {
            $styleNode = $p.SelectSingleNode('w:pPr/w:pStyle', $ns)
            $style = ''

            if ($null -ne $styleNode) {
                $style = $styleNode.GetAttribute('val', $nsUri)
            }

            if ($style -match '^TOC[1-9]$') {
                # Read only the TOC entry title, not the page number.
                # Word Vim writes the page number after a real w:tab.
                # Joining every w:t used to produce strings such as
                # "Spring Boot3", while Pandoc exposed "Spring Boot 3".
                # That mismatch prevented the editor from collapsing the
                # field result and caused TOC copies to accumulate on save.
                $parts = @()

                foreach ($node in $p.SelectNodes('.//*', $ns)) {
                    if ($node.LocalName -eq 'tab') {
                        break
                    }

                    if ($node.LocalName -eq 't') {
                        $parts += $node.InnerText
                    }
                }

                $text = ($parts -join '')

                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $b64 = [Convert]::ToBase64String(
                        [System.Text.Encoding]::UTF8.GetBytes($text)
                    )

                    Write-Output ('ENTRY' + "`t" + $b64)
                }
            }
        }

        $ended = $false

        foreach ($fld in $p.SelectNodes('.//w:fldChar', $ns)) {
            if ($fld.GetAttribute('fldCharType', $nsUri) -eq 'end') {
                $ended = $true
                break
            }
        }

        if ($ended) {
            break
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

  if not ok or output == "" then
    return nil
  end

  local info = {
    title = DEFAULT_TITLE,
    entries = {},
  }

  for line in output:gmatch("[^\r\n]+") do
    local kind, b64 =
      line:match("^(%u+)\t(.+)$")

    if kind and b64 then
      local ok_decode, text =
        pcall(vim.base64.decode, b64)

      if ok_decode then
        if kind == "TITLE" then
          info.title = text
        elseif kind == "ENTRY" then
          table.insert(info.entries, text)
        end
      end
    end
  end

  return info
end

function M.restore_editor_lines(buf, lines, assignments, docx)
  local info = inspect_docx_toc(docx)

  pending_open[buf] = nil

  if not info then
    return lines, assignments
  end

  local title_row = nil
  local wanted_title =
    normalize_text(info.title)

  for i, line in ipairs(lines) do
    if normalize_text(line) == wanted_title then
      title_row = i - 1
      break
    end
  end

  if title_row == nil then
    return lines, assignments
  end

  local wanted_entries = {}
  for _, entry in ipairs(info.entries or {}) do
    local wanted = normalize_text(entry)
    if wanted ~= "" then
      table.insert(wanted_entries, wanted)
    end
  end

  -- A DOCX TOC is a Word field. Pandoc also emits the cached field result
  -- as ordinary Markdown lines. Those lines must never remain as real
  -- editor paragraphs, otherwise the next :w writes them back as document
  -- text and another TOC is inserted above them. Repeating that cycle is
  -- what caused the TOC to be copied and pushed lower on every reopen.
  --
  -- Remove the entire TOC-result region immediately following the title.
  -- This also repairs documents that already contain several stale copies
  -- created by v5.3.
  local function matches_toc_entry(line)
    local candidate = normalize_text(line)

    for _, wanted in ipairs(wanted_entries) do
      if candidate == wanted then
        return true
      end

      if candidate:sub(1, #wanted) == wanted then
        local rest = vim.trim(candidate:sub(#wanted + 1))

        -- Pandoc may represent the Word tab leader as spaces/dots and then
        -- the cached page number. Accept both "Title 3" and
        -- "Title ........ 3" forms.
        if rest:match("^%d+$") or rest:match("^[%.·…%s]+%d+$") then
          return true
        end
      end
    end

    return false
  end

  local remove = {}
  local i = title_row + 2 -- Lua index of the first line after title.
  local saw_toc_line = false

  local function looks_like_cached_toc_line(line)
    local candidate = normalize_text(line)

    if candidate == "" then
      return false
    end

    -- Word/Pandoc may expose the cached TOC result in several forms:
    --   Heading 3
    --   Heading ........ 3
    --   Heading <tab> 3
    -- Exact title matching is preferred, but older Word/Pandoc versions
    -- can rewrite hyperlink runs/styles enough that inspect_docx_toc()
    -- does not recover the same title text.  While we are directly after
    -- a *real Word TOC field* title, a trailing page number is therefore a
    -- safe fallback for identifying the cached field-result paragraphs.
    return candidate:match("%s%d+$") ~= nil
      or candidate:match("[%.·…]%s*%d+$") ~= nil
  end

  while i <= #lines do
    local candidate = normalize_text(lines[i])

    if matches_toc_entry(lines[i]) or looks_like_cached_toc_line(lines[i]) then
      remove[i - 1] = true
      saw_toc_line = true
      i = i + 1
    elseif saw_toc_line and candidate == wanted_title then
      -- v5.3/v5.4 could have persisted another TOC title between
      -- duplicate cached result blocks. Keep the first anchor title only.
      remove[i - 1] = true
      i = i + 1
    else
      break
    end
  end

  local new_lines = {}
  local old_to_new = {}

  for old_row = 0, #lines - 1 do
    if not remove[old_row] then
      old_to_new[old_row] = #new_lines
      table.insert(new_lines, lines[old_row + 1])
    end
  end

  local new_assignments = {}

  for _, item in ipairs(assignments or {}) do
    local new_row = old_to_new[item.row]

    if new_row ~= nil then
      table.insert(new_assignments, {
        row = new_row,
        style = item.style,
      })
    end
  end

  pending_open[buf] = old_to_new[title_row] or title_row

  return new_lines, new_assignments
end

function M.finish_open(buf)
  local row = pending_open[buf]
  pending_open[buf] = nil

  if row ~= nil then
    set_anchor(buf, row)
  end
end

-- ------------------------------------------------------------
-- DOCX save
-- ------------------------------------------------------------

function M.apply_to_docx(docx, buf)
  if not M.has_toc(buf) then
    return true
  end

  local entries = M.entries(buf)
  local specs_path = vim.fn.tempname() .. ".tsv"
  local spec_lines = {}

  for _, entry in ipairs(entries) do
    local b64 =
      vim.base64.encode(entry.title)

    table.insert(
      spec_lines,
      table.concat({
        tostring(entry.level),
        tostring(entry.page or 1),
        b64,
      }, "\t")
    )
  end

  vim.fn.writefile(spec_lines, specs_path)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$specPath = '%s'
$markerPrefix = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$titleText = '%s'

function New-WElement($xml, $name) {
    return $xml.CreateElement('w', $name, $nsUri)
}

function Set-WVal($node, $name, $value) {
    [void]$node.SetAttribute($name, $nsUri, [string]$value)
}

function New-TextRun($xml, $text) {
    $r = New-WElement $xml 'r'
    $t = New-WElement $xml 't'
    $t.InnerText = [string]$text
    [void]$r.AppendChild($t)
    return $r
}

function New-FieldCharRun($xml, $kind, $dirty) {
    $r = New-WElement $xml 'r'
    $fld = New-WElement $xml 'fldChar'
    Set-WVal $fld 'fldCharType' $kind

    if ($dirty) {
        Set-WVal $fld 'dirty' 'true'
    }

    [void]$r.AppendChild($fld)
    return $r
}

function New-InstructionRun($xml, $text) {
    $r = New-WElement $xml 'r'
    $instr = New-WElement $xml 'instrText'
    $instr.InnerText = $text
    [void]$r.AppendChild($instr)
    return $r
}

function New-TabRun($xml) {
    $r = New-WElement $xml 'r'
    $tab = New-WElement $xml 'tab'
    [void]$r.AppendChild($tab)
    return $r
}

$specs = @()

if (Test-Path -LiteralPath $specPath) {
    foreach ($line in Get-Content -LiteralPath $specPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t", 3

        if ($parts.Count -lt 3) {
            continue
        }

        $title = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($parts[2])
        )

        $specs += [PSCustomObject]@{
            Level = [int]$parts[0]
            Page = [int]$parts[1]
            Title = $title
        }
    }
}

$zipRead = $null
$reader = $null

try {
    $zipRead = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zipRead.GetEntry('word/document.xml')

    if ($null -eq $entry) {
        throw 'word/document.xml not found'
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $zipRead) { $zipRead.Dispose() }
}

$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('w', $nsUri)

$body = $xml.SelectSingleNode('/w:document/w:body', $ns)
$marker = $null

foreach ($p in $body.SelectNodes('w:p', $ns)) {
    $parts = @()
    foreach ($t in $p.SelectNodes('.//w:t', $ns)) {
        $parts += $t.InnerText
    }

    $text = ($parts -join '')

    if ($text.StartsWith($markerPrefix)) {
        $marker = $p
        break
    }
}

if ($null -eq $marker) {
    throw 'Word Vim TOC marker paragraph was not found after Pandoc conversion'
}

# Calculate right-aligned page-number tab from section geometry.
$tabPos = 9000
$sectPr = $body.SelectSingleNode('w:sectPr', $ns)

if ($null -ne $sectPr) {
    $pgSz = $sectPr.SelectSingleNode('w:pgSz', $ns)
    $pgMar = $sectPr.SelectSingleNode('w:pgMar', $ns)

    if ($null -ne $pgSz -and $null -ne $pgMar) {
        $pageW = [int]$pgSz.GetAttribute('w', $nsUri)
        $left = [int]$pgMar.GetAttribute('left', $nsUri)
        $right = [int]$pgMar.GetAttribute('right', $nsUri)

        if ($pageW -gt 0) {
            $tabPos = [Math]::Max(1440, $pageW - $left - $right)
        }
    }
}

# Title paragraph.
$titleP = New-WElement $xml 'p'
$titlePPr = New-WElement $xml 'pPr'
$titleStyle = New-WElement $xml 'pStyle'
Set-WVal $titleStyle 'val' 'TOCHeading'
[void]$titlePPr.AppendChild($titleStyle)
[void]$titleP.AppendChild($titlePPr)
[void]$titleP.AppendChild((New-TextRun $xml $titleText))

[void]$body.InsertBefore($titleP, $marker)

if ($specs.Count -eq 0) {
    $specs = @(
        [PSCustomObject]@{
            Level = 1
            Page = 1
            Title = 'Нет заголовков Heading 1-3'
        }
    )
}

$resultParagraphs = @()

for ($i = 0; $i -lt $specs.Count; $i++) {
    $spec = $specs[$i]
    $level = [Math]::Max(1, [Math]::Min(3, [int]$spec.Level))

    $p = New-WElement $xml 'p'
    $pPr = New-WElement $xml 'pPr'

    $pStyle = New-WElement $xml 'pStyle'
    Set-WVal $pStyle 'val' ('TOC' + $level)
    [void]$pPr.AppendChild($pStyle)

    $tabs = New-WElement $xml 'tabs'
    $tabStop = New-WElement $xml 'tab'
    Set-WVal $tabStop 'val' 'right'
    Set-WVal $tabStop 'leader' 'dot'
    Set-WVal $tabStop 'pos' $tabPos
    [void]$tabs.AppendChild($tabStop)
    [void]$pPr.AppendChild($tabs)

    [void]$p.AppendChild($pPr)

    if ($i -eq 0) {
        [void]$p.AppendChild((New-FieldCharRun $xml 'begin' $true))
        [void]$p.AppendChild((New-InstructionRun $xml ' TOC \o "1-3" \h \z \u '))
        [void]$p.AppendChild((New-FieldCharRun $xml 'separate' $false))
    }

    [void]$p.AppendChild((New-TextRun $xml $spec.Title))
    [void]$p.AppendChild((New-TabRun $xml))
    [void]$p.AppendChild((New-TextRun $xml ([string]$spec.Page)))

    if ($i -eq ($specs.Count - 1)) {
        [void]$p.AppendChild((New-FieldCharRun $xml 'end' $false))
    }

    $resultParagraphs += $p
}

foreach ($p in $resultParagraphs) {
    [void]$body.InsertBefore($p, $marker)
}

[void]$body.RemoveChild($marker)

# Validate the in-memory DOM BEFORE serializing it.
# This avoids reparsing OuterXml through PowerShell [xml], which can
# reject automatically generated namespace prefixes on xml:space.
$allText = ''

foreach ($t in $xml.SelectNodes('//w:t', $ns)) {
    $allText += $t.InnerText
}

if ($allText.Contains($markerPrefix)) {
    throw 'TOC marker remained in document.xml'
}

$foundTOC = $false

foreach ($instr in $xml.SelectNodes('//w:instrText', $ns)) {
    if ($instr.InnerText -match '(^|\s)TOC(\s|$)') {
        $foundTOC = $true
        break
    }
}

if (-not $foundTOC) {
    throw 'TOC field instruction was not created'
}

# Save with XmlWriter rather than DocumentElement.OuterXml.
# XmlWriter keeps namespace declarations consistent and writes UTF-8
# without an unwanted UTF-16 declaration.
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$settings.Indent = $false
$settings.OmitXmlDeclaration = $true

$stringBuilder = New-Object System.Text.StringBuilder
$stringWriter = New-Object System.IO.StringWriter($stringBuilder, [System.Globalization.CultureInfo]::InvariantCulture)
$xmlWriter = [System.Xml.XmlWriter]::Create($stringWriter, $settings)

try {
    $xml.DocumentElement.WriteTo($xmlWriter)
    $xmlWriter.Flush()
}
finally {
    if ($null -ne $xmlWriter) {
        $xmlWriter.Dispose()
    }
    if ($null -ne $stringWriter) {
        $stringWriter.Dispose()
    }
}

$newXml = $stringBuilder.ToString()

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

    $oldEntry = $zipUpdate.GetEntry('word/document.xml')
    $oldEntry.Delete()

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
    if ($null -ne $writer) { $writer.Dispose() }
    if ($null -ne $zipUpdate) { $zipUpdate.Dispose() }
    if ($null -ne $fileStream) { $fileStream.Dispose() }
}

# ZIP-level validation: document.xml must still be readable text and
# contain the TOC instruction. Do not cast it back through [xml] here.
$zipCheck = $null
$checkReader = $null

try {
    $zipCheck = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zipCheck.GetEntry('word/document.xml')

    if ($null -eq $entry) {
        throw 'word/document.xml missing after TOC update'
    }

    $checkReader = New-Object System.IO.StreamReader($entry.Open())
    $checkText = $checkReader.ReadToEnd()

    if ($checkText -notmatch '<w:document') {
        throw 'Invalid document.xml after TOC update'
    }

    if ($checkText -notmatch 'TOC') {
        throw 'TOC instruction missing after ZIP update'
    }

    if ($checkText.Contains($markerPrefix)) {
        throw 'TOC marker remained after ZIP update'
    }
}
finally {
    if ($null -ne $checkReader) { $checkReader.Dispose() }
    if ($null -ne $zipCheck) { $zipCheck.Dispose() }
}
]],
    ps_escape(docx),
    ps_escape(specs_path),
    MARKER_PREFIX,
    ps_escape(DEFAULT_TITLE)
  )

  local ok, output =
    run_powershell(script)

  pcall(vim.fn.delete, specs_path)

  if not ok then
    vim.notify(
      "Word Vim: could not create Table of Contents:\n"
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
    "<leader>tc",
    M.insert,
    {
      buffer = buf,
      silent = true,
      desc = "Word Vim: insert Table of Contents",
    }
  )

  vim.keymap.set(
    "n",
    "<leader>td",
    M.delete,
    {
      buffer = buf,
      silent = true,
      desc = "Word Vim: delete Table of Contents",
    }
  )

  vim.keymap.set(
    "n",
    "<leader>to",
    M.toggle_outline,
    {
      buffer = buf,
      silent = true,
      desc = "Word Vim: toggle contents window",
    }
  )
end

function M.detach(buf)
  local s = state[buf]

  if s then
    close_outline(buf)
  end

  if s and s.timer then
    pcall(function()
      s.timer:stop()
      s.timer:close()
    end)
  end

  state[buf] = nil
  pending_open[buf] = nil
end

function M.setup()
  vim.api.nvim_create_user_command(
    "WordTOC",
    M.insert,
    {
      desc = "Insert Word Table of Contents",
    }
  )

  vim.api.nvim_create_user_command(
    "WordTOCDelete",
    M.delete,
    {
      desc = "Delete Word Table of Contents",
    }
  )

  vim.api.nvim_create_user_command(
    "WordTOCRefresh",
    function()
      local buf = vim.api.nvim_get_current_buf()
      M.refresh(buf)
      M.refresh_outline(buf)

      local ok_pages, pagebreaks =
        pcall(require, "wordvim.pagebreaks")

      if ok_pages then
        pagebreaks.recalculate(buf)
      end
    end,
    {
      desc = "Refresh Word Vim Table of Contents preview",
    }
  )

  vim.api.nvim_create_user_command(
    "WordTOCWindow",
    M.toggle_outline,
    {
      desc = "Toggle Word Vim contents navigation window",
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
        if
          vim.b[args.buf].docx_original_file
          and M.has_toc(args.buf)
        then
          schedule_refresh(args.buf)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "WinResized",
    {
      callback = function()
        local buf = vim.api.nvim_get_current_buf()

        if M.has_toc(buf) then
          M.refresh(buf)
        end
      end,
    }
  )
end

return M
