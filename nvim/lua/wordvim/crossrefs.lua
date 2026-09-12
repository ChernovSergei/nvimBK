-- ============================================================
-- lua/wordvim/crossrefs.lua
--
-- Word captions and cross-references for figures and tables.
--
-- Normal mode:
--   Space c f   add Figure caption
--   Space c t   add Table caption
--   Space r f   insert Figure cross-reference
--   Space r t   insert Table cross-reference
--
-- Cross-reference display:
--   Figure 2, page 34
--   Table 3, page 17
--
-- DOCX output:
--   Caption number: SEQ field inside a bookmark.
--   Cross-reference: REF bookmark + PAGEREF bookmark.
-- ============================================================

local M = {}

local ns = vim.api.nvim_create_namespace("WordVimCrossRefs")
local state = {}
local augroup = vim.api.nvim_create_augroup("WordVimCrossRefs", { clear = false })

local CAP_MARKER_PREFIX = "WORDVIMCAPTIONTOKEN"
local REF_MARKER_PREFIX = "WORDVIMXREFTOKEN"
local EM_DASH = " — "

local function get_state(buf)
  if not state[buf] then
    state[buf] = {
      captions = {},
      refs = {},
      picker_buf = nil,
      picker_win = nil,
      picker_rows = {},
      picker_kind = nil,
      source_win = nil,
      timer = nil,
      updating = false,
      save_captions = {},
      save_refs = {},
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

local function kind_label(kind)
  return kind == "table" and "Table" or "Figure"
end

local function safe_uid(kind)
  local stamp = tostring(vim.uv.hrtime())
  local rnd = tostring(math.random(100000, 999999))
  return "_WordVim_" .. kind_label(kind) .. "_" .. stamp .. "_" .. rnd
end

local function caption_pos(buf, id)
  local ok, pos = pcall(
    vim.api.nvim_buf_get_extmark_by_id,
    buf,
    ns,
    id,
    { details = true }
  )

  if not ok or not pos or #pos < 2 then
    return nil
  end

  return {
    row = pos[1],
    col = pos[2],
    details = pos[3] or {},
  }
end

local function ref_pos(buf, id)
  return caption_pos(buf, id)
end

local function sorted_caption_items(buf, kind)
  local s = get_state(buf)
  local items = {}

  for id, meta in pairs(s.captions) do
    if not kind or meta.kind == kind then
      local pos = caption_pos(buf, id)
      if pos then
        table.insert(items, {
          id = id,
          row = pos.row,
          kind = meta.kind,
          bookmark = meta.bookmark,
        })
      end
    end
  end

  table.sort(items, function(a, b)
    if a.row == b.row then
      return a.id < b.id
    end
    return a.row < b.row
  end)

  return items
end

local function sorted_ref_items(buf)
  local s = get_state(buf)
  local items = {}

  for id, meta in pairs(s.refs) do
    local pos = ref_pos(buf, id)
    if pos then
      table.insert(items, {
        id = id,
        row = pos.row,
        col = pos.col,
        end_row = pos.details.end_row or pos.row,
        end_col = pos.details.end_col or pos.col,
        kind = meta.kind,
        bookmark = meta.bookmark,
      })
    end
  end

  table.sort(items, function(a, b)
    if a.row == b.row then
      return a.col < b.col
    end
    return a.row < b.row
  end)

  return items
end

local function caption_number(buf, id)
  local meta = get_state(buf).captions[id]
  if not meta then
    return nil
  end

  local number = 0
  for _, item in ipairs(sorted_caption_items(buf, meta.kind)) do
    number = number + 1
    if item.id == id then
      return number
    end
  end

  return nil
end

local function caption_title_from_line(line, kind)
  line = tostring(line or "")
  local label = kind_label(kind)

  local title = line:match("^%s*" .. label .. "%s+%d+%s+—%s*(.*)$")
  if title then
    return vim.trim(title)
  end

  title = line:match("^%s*" .. label .. "%s+%d+%s*[:%-]%s*(.*)$")
  if title then
    return vim.trim(title)
  end

  return vim.trim(line)
end

local function caption_info_by_bookmark(buf, bookmark)
  local s = get_state(buf)

  for id, meta in pairs(s.captions) do
    if meta.bookmark == bookmark then
      local pos = caption_pos(buf, id)
      if pos then
        local line = vim.api.nvim_buf_get_lines(buf, pos.row, pos.row + 1, false)[1] or ""
        local number = caption_number(buf, id) or 1
        local page = 1
        local ok_pages, pagebreaks = pcall(require, "wordvim.pagebreaks")
        if ok_pages then
          page = select(1, pagebreaks.page_info(buf, pos.row)) or 1
        end

        return {
          id = id,
          row = pos.row,
          kind = meta.kind,
          bookmark = bookmark,
          number = number,
          title = caption_title_from_line(line, meta.kind),
          page = page,
        }
      end
    end
  end

  return nil
end

local function set_caption_mark(buf, row, kind, bookmark)
  local s = get_state(buf)
  -- Keep caption metadata attached to the original caption paragraph when a
  -- new paragraph is inserted exactly before it (for example with O).
  -- With left gravity the mark stays on the newly inserted row and refresh()
  -- rewrites that row as another caption, duplicating the visible caption.
  local id = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
    right_gravity = true,
  })

  s.captions[id] = {
    kind = kind,
    bookmark = bookmark or safe_uid(kind),
  }

  return id
end

local function set_ref_mark(buf, row, start_col, end_col, kind, bookmark)
  local s = get_state(buf)
  local id = vim.api.nvim_buf_set_extmark(buf, ns, row, start_col, {
    end_row = row,
    end_col = end_col,
    -- Follow the referenced text if a new paragraph/text is inserted exactly
    -- at the start boundary. This mirrors paragraph-style/caption behavior.
    right_gravity = true,
    end_right_gravity = true,
  })

  s.refs[id] = {
    kind = kind,
    bookmark = bookmark,
  }

  return id
end

local function close_picker(buf)
  local s = get_state(buf)

  if s.picker_win and vim.api.nvim_win_is_valid(s.picker_win) then
    pcall(vim.api.nvim_win_close, s.picker_win, true)
  end

  if s.picker_buf and vim.api.nvim_buf_is_valid(s.picker_buf) then
    pcall(vim.api.nvim_buf_delete, s.picker_buf, { force = true })
  end

  s.picker_buf = nil
  s.picker_win = nil
  s.picker_rows = {}
  s.picker_kind = nil
  s.source_win = nil
end

local function display_ref(info)
  return kind_label(info.kind) .. " " .. tostring(info.number) .. ", page " .. tostring(info.page)
end

function M.refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local s = get_state(buf)
  if s.updating then
    return
  end

  s.updating = true

  local ok, err = pcall(function()
    -- Normalize caption numbering and visible caption text.
    for _, kind in ipairs({ "figure", "table" }) do
      local n = 0
      for _, item in ipairs(sorted_caption_items(buf, kind)) do
        n = n + 1
        local line = vim.api.nvim_buf_get_lines(buf, item.row, item.row + 1, false)[1] or ""
        local title = caption_title_from_line(line, kind)
        local wanted = kind_label(kind) .. " " .. tostring(n)
        if title ~= "" then
          wanted = wanted .. EM_DASH .. title
        end

        if line ~= wanted then
          -- A caption extmark uses right_gravity=true so that inserting a new
          -- paragraph exactly before the caption (O / Shift+O) keeps the mark
          -- attached to the original caption paragraph.  Replacing the whole
          -- caption line while that mark is still present, however, is also an
          -- insertion at the mark boundary.  Neovim can therefore move the
          -- mark to the following row.  The next refresh then treats that row
          -- as the caption and rewrites it too, producing a cascade of
          -- duplicate "Figure N" lines.
          --
          -- Remove the mark while normalising its own visible text and recreate
          -- it on the same row afterwards.  This preserves right-gravity for
          -- user edits without allowing refresh() to move its own metadata.
          local meta = s.captions[item.id]
          if meta then
            local kind_meta = meta.kind
            local bookmark_meta = meta.bookmark
            pcall(vim.api.nvim_buf_del_extmark, buf, ns, item.id)
            s.captions[item.id] = nil
            vim.api.nvim_buf_set_lines(buf, item.row, item.row + 1, false, { wanted })
            set_caption_mark(buf, item.row, kind_meta, bookmark_meta)
          else
            vim.api.nvim_buf_set_lines(buf, item.row, item.row + 1, false, { wanted })
          end
        end
      end
    end

    -- Refresh the visible REF + PAGEREF text. Work from the end of the
    -- document so changing one reference cannot invalidate later columns.
    local refs = sorted_ref_items(buf)
    table.sort(refs, function(a, b)
      if a.row == b.row then
        return a.col > b.col
      end
      return a.row > b.row
    end)

    for _, item in ipairs(refs) do
      local info = caption_info_by_bookmark(buf, item.bookmark)
      if info then
        local wanted = display_ref(info)
        local pos = ref_pos(buf, item.id)

        if pos then
          local line_count = vim.api.nvim_buf_line_count(buf)
          local erow = pos.details.end_row or pos.row
          local ecol = pos.details.end_col or pos.col

          -- A user may delete a REF with ordinary editing commands instead of
          -- Word Vim's dd wrapper. In that case Neovim keeps the extmark, but
          -- its old range can collapse or point past the new end of the line.
          -- Calling nvim_buf_get_text() with that stale range raises
          -- "Index out of bounds". Treat such a collapsed/stale range as a
          -- deleted cross-reference and remove its metadata instead of trying
          -- to recreate the visible REF text.
          local stale = false

          if pos.row < 0 or pos.row >= line_count then
            stale = true
          elseif erow ~= pos.row then
            stale = true
          else
            local line = vim.api.nvim_buf_get_lines(buf, pos.row, pos.row + 1, false)[1] or ""
            local line_len = #line

            if pos.col < 0 or pos.col > line_len then
              stale = true
            elseif ecol < pos.col or ecol > line_len then
              stale = true
            elseif ecol == pos.col then
              stale = true
            end
          end

          if stale then
            pcall(vim.api.nvim_buf_del_extmark, buf, ns, item.id)
            s.refs[item.id] = nil
          else
            local existing = vim.api.nvim_buf_get_text(
              buf,
              pos.row,
              pos.col,
              erow,
              ecol,
              {}
            )
            local existing_text = table.concat(existing, "\n")

            if existing_text ~= wanted then
              vim.api.nvim_buf_set_text(
                buf,
                pos.row,
                pos.col,
                erow,
                ecol,
                { wanted }
              )

              pcall(vim.api.nvim_buf_del_extmark, buf, ns, item.id)
              s.refs[item.id] = nil
              set_ref_mark(
                buf,
                pos.row,
                pos.col,
                pos.col + #wanted,
                item.kind,
                item.bookmark
              )
            end
          end
        end
      end
    end
  end)

  s.updating = false

  if not ok then
    vim.schedule(function()
      vim.notify("Word Vim cross-reference refresh failed: " .. tostring(err), vim.log.levels.ERROR)
    end)
  end
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

  timer:start(280, 0, vim.schedule_wrap(function()
    if s.timer == timer then
      s.timer = nil
    end

    pcall(function()
      timer:stop()
      timer:close()
    end)

    if vim.api.nvim_buf_is_valid(buf) then
      M.refresh(buf)
    end
  end))
end

local function insert_caption(kind)
  local buf = vim.api.nvim_get_current_buf()

  if not vim.b[buf].docx_original_file then
    vim.notify("Word Vim: captions are available for DOCX buffers", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = kind_label(kind) .. " caption: " }, function(input)
    if input == nil then
      return
    end

    input = vim.trim(input)
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local insert_row = cursor_row + 1

    if kind == "table" then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local row = cursor_row
      if (lines[row + 1] or ""):match("^%s*|.*|%s*$") then
        while row > 0 and (lines[row] or ""):match("^%s*|.*|%s*$") do
          row = row - 1
        end
        if not (lines[row + 1] or ""):match("^%s*|.*|%s*$") then
          row = row + 1
        end
        insert_row = row
      else
        insert_row = cursor_row
      end
    end

    vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, { input })

    -- A Word caption is not only cross-reference metadata; it is also a
    -- paragraph with the Word paragraph style "caption".  Keep the style
    -- metadata in sync at creation time so the Style UI immediately shows
    -- Caption instead of Normal.
    local ok_styles, styles = pcall(require, "wordvim.styles")
    if ok_styles and styles and styles.set_paragraph_style then
      styles.set_paragraph_style(buf, insert_row, "caption")
    end

    set_caption_mark(buf, insert_row, kind, nil)
    M.refresh(buf)

    -- refresh() may replace the whole caption line while normalising its
    -- visible number. Paragraph-style extmarks also use right_gravity=true,
    -- so that replacement can move the style mark to the following row.
    -- Re-assert Caption after refresh so the caption paragraph itself always
    -- owns the Word Caption style.
    if ok_styles and styles and styles.set_paragraph_style then
      styles.set_paragraph_style(buf, insert_row, "caption")
    end

    pcall(vim.api.nvim_win_set_cursor, 0, { insert_row + 1, 0 })
  end)
end

function M.insert_figure_caption()
  insert_caption("figure")
end

function M.insert_table_caption()
  insert_caption("table")
end

local function insert_reference(buf, info)
  local s = get_state(buf)
  local target_win = s.source_win

  if not target_win or not vim.api.nvim_win_is_valid(target_win) then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      if vim.api.nvim_win_is_valid(win) and win ~= s.picker_win then
        target_win = win
        break
      end
    end
  end

  if not target_win or not vim.api.nvim_win_is_valid(target_win) then
    close_picker(buf)
    return
  end

  close_picker(buf)
  vim.api.nvim_set_current_win(target_win)

  local pos = vim.api.nvim_win_get_cursor(target_win)
  local row = pos[1] - 1
  local col = pos[2]
  local text = display_ref(info)

  vim.api.nvim_buf_set_text(buf, row, col, row, col, { text })
  set_ref_mark(buf, row, col, col + #text, info.kind, info.bookmark)
  vim.api.nvim_win_set_cursor(target_win, { row + 1, col + #text })
end

local function open_reference_picker(kind)
  local buf = vim.api.nvim_get_current_buf()

  if not vim.b[buf].docx_original_file then
    vim.notify("Word Vim: cross-references are available for DOCX buffers", vim.log.levels.WARN)
    return
  end

  local s = get_state(buf)
  close_picker(buf)

  local items = {}
  for _, cap in ipairs(sorted_caption_items(buf, kind)) do
    local info = caption_info_by_bookmark(buf, cap.bookmark)
    if info then
      table.insert(items, info)
    end
  end

  if #items == 0 then
    vim.notify("Word Vim: no " .. kind_label(kind) .. " captions found", vim.log.levels.WARN)
    return
  end

  s.source_win = vim.api.nvim_get_current_win()
  s.picker_kind = kind
  s.picker_rows = items

  local picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype = "nofile"
  vim.bo[picker_buf].bufhidden = "wipe"
  vim.bo[picker_buf].swapfile = false
  vim.bo[picker_buf].filetype = "wordvim-crossref"

  local lines = {}
  local width = 42
  for _, info in ipairs(items) do
    local line = kind_label(info.kind) .. " " .. tostring(info.number) .. EM_DASH .. info.title
      .. "  [page " .. tostring(info.page) .. "]"
    table.insert(lines, line)
    width = math.max(width, vim.fn.strdisplaywidth(line) + 4)
  end

  width = math.min(math.max(42, width), math.max(42, vim.o.columns - 10))
  local height = math.min(math.max(6, #lines + 2), math.max(6, vim.o.lines - 8))
  local row = math.max(1, math.floor((vim.o.lines - height) / 2 - 1))
  local col = math.max(1, math.floor((vim.o.columns - width) / 2))

  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].modifiable = false

  local picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Select " .. kind_label(kind) .. " ",
    title_pos = "center",
  })

  vim.wo[picker_win].number = false
  vim.wo[picker_win].relativenumber = false
  vim.wo[picker_win].wrap = false
  vim.wo[picker_win].cursorline = true
  vim.wo[picker_win].signcolumn = "no"
  vim.wo[picker_win].foldcolumn = "0"

  s.picker_buf = picker_buf
  s.picker_win = picker_win

  local function choose()
    if not s.picker_win or not vim.api.nvim_win_is_valid(s.picker_win) then
      return
    end
    local idx = vim.api.nvim_win_get_cursor(s.picker_win)[1]
    local info = s.picker_rows[idx]
    if info then
      insert_reference(buf, info)
    end
  end

  vim.keymap.set("n", "<CR>", choose, { buffer = picker_buf, silent = true })
  vim.keymap.set("n", "e", choose, { buffer = picker_buf, silent = true })
  vim.keymap.set("n", "q", function() close_picker(buf) end, { buffer = picker_buf, silent = true })
  vim.keymap.set("n", "<Esc>", function() close_picker(buf) end, { buffer = picker_buf, silent = true })
end

function M.insert_figure_reference()
  open_reference_picker("figure")
end

function M.insert_table_reference()
  open_reference_picker("table")
end

function M.clear_range_metadata(buf, first_row, last_row)
  local s = get_state(buf)
  first_row = math.max(0, tonumber(first_row) or 0)
  last_row = math.max(first_row, tonumber(last_row) or first_row)

  local delete_caps = {}
  for id, _ in pairs(s.captions) do
    local pos = caption_pos(buf, id)
    if pos and pos.row >= first_row and pos.row <= last_row then
      table.insert(delete_caps, id)
    end
  end
  for _, id in ipairs(delete_caps) do
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
    s.captions[id] = nil
  end

  local delete_refs = {}
  for id, _ in pairs(s.refs) do
    local pos = ref_pos(buf, id)
    if pos and pos.row >= first_row and pos.row <= last_row then
      table.insert(delete_refs, id)
    end
  end
  for _, id in ipairs(delete_refs) do
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
    s.refs[id] = nil
  end
end

function M.prepare_markdown_lines(buf, input_lines)
  M.refresh(buf)

  local s = get_state(buf)
  local lines = vim.deepcopy(input_lines)
  s.save_captions = {}
  s.save_refs = {}

  local captions = sorted_caption_items(buf)
  for i, item in ipairs(captions) do
    local line = lines[item.row + 1] or ""
    local info = caption_info_by_bookmark(buf, item.bookmark)
    if info then
      local marker = CAP_MARKER_PREFIX .. string.format("%04d", i)
      s.save_captions[marker] = info
      lines[item.row + 1] = marker
    end
  end

  local refs = sorted_ref_items(buf)
  local by_row = {}
  for i, item in ipairs(refs) do
    local marker = REF_MARKER_PREFIX .. string.format("%04d", i)
    local info = caption_info_by_bookmark(buf, item.bookmark)
    if info then
      s.save_refs[marker] = {
        kind = item.kind,
        bookmark = item.bookmark,
        number = info.number,
        page = info.page,
      }
      by_row[item.row] = by_row[item.row] or {}
      table.insert(by_row[item.row], {
        start_col = item.col,
        end_col = item.end_col,
        marker = marker,
      })
    end
  end

  for row, row_items in pairs(by_row) do
    table.sort(row_items, function(a, b) return a.start_col > b.start_col end)
    local line = lines[row + 1] or ""
    for _, item in ipairs(row_items) do
      line = line:sub(1, item.start_col) .. item.marker .. line:sub(item.end_col + 1)
    end
    lines[row + 1] = line
  end

  return lines
end

local function inspect_docx(docx)
  local temp = vim.fn.tempname() .. ".docx"
  local copied = vim.uv.fs_copyfile(docx, temp)
  if not copied then
    return { captions = {}, refs = {} }
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
    if ($null -eq $entry) { exit 0 }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    foreach ($p in $xml.SelectNodes('/w:document/w:body/w:p', $ns)) {
        $visibleParts = @()
        foreach ($t in $p.SelectNodes('.//w:t', $ns)) { $visibleParts += $t.InnerText }
        $visible = ($visibleParts -join '')

        $instrs = @()
        foreach ($instr in $p.SelectNodes('.//w:instrText', $ns)) { $instrs += $instr.InnerText }
        $allInstr = ($instrs -join ' ')

        if ($allInstr -match 'SEQ\s+(Figure|Table)') {
            $kind = $Matches[1]
            $bookmark = ''
            foreach ($bm in $p.SelectNodes('.//w:bookmarkStart', $ns)) {
                $name = $bm.GetAttribute('name', $nsUri)
                if ($name -match '^_WordVim_(Figure|Table)_') {
                    $bookmark = $name
                    break
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($bookmark)) {
                $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($visible))
                Write-Output ('CAP' + "`t" + $kind + "`t" + $bookmark + "`t" + $b64)
            }
        }

        foreach ($instr in $instrs) {
            if ($instr -match '^\s*REF\s+(_WordVim_(Figure|Table)_[^\s\\]+)') {
                $bookmark = $Matches[1]
                $kind = $Matches[2]
                Write-Output ('REF' + "`t" + $kind + "`t" + $bookmark)
            }
        }
    }
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $zip) { $zip.Dispose() }
}
]], ps_escape(temp))

  local ok, output = run_powershell(script)
  pcall(vim.fn.delete, temp)

  local result = { captions = {}, refs = {} }
  if not ok then
    return result
  end

  for line in output:gmatch("[^\r\n]+") do
    local fields = vim.split(line, "\t", { plain = true })
    if fields[1] == "CAP" and #fields >= 4 then
      local visible = ""
      pcall(function() visible = vim.base64.decode(fields[4]) end)
      table.insert(result.captions, {
        kind = fields[2]:lower(),
        bookmark = fields[3],
        visible = visible,
      })
    elseif fields[1] == "REF" and #fields >= 3 then
      table.insert(result.refs, {
        kind = fields[2]:lower(),
        bookmark = fields[3],
      })
    end
  end

  return result
end

function M.restore_from_docx(buf, docx)
  local s = get_state(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  s.captions = {}
  s.refs = {}

  local info = inspect_docx(docx)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local used_rows = {}

  for _, cap in ipairs(info.captions) do
    local found = nil

    for i, line in ipairs(lines) do
      local row = i - 1
      if not used_rows[row] and line == cap.visible then
        found = row
        break
      end
    end

    if found == nil then
      local label = kind_label(cap.kind)
      for i, line in ipairs(lines) do
        local row = i - 1
        if not used_rows[row] and line:match("^%s*" .. label .. "%s+%d+") then
          found = row
          break
        end
      end
    end

    if found ~= nil then
      used_rows[found] = true

      -- Pandoc can flatten/reconstruct a figure caption in a way that leaves
      -- the visible paragraph as Normal in the editor even though the DOCX
      -- caption metadata (SEQ/bookmark) was restored successfully.  Once we
      -- have authoritatively matched a DOCX caption, restore its Word
      -- paragraph style as well.
      local ok_styles, styles = pcall(require, "wordvim.styles")
      if ok_styles and styles and styles.set_paragraph_style then
        styles.set_paragraph_style(buf, found, "caption")
      end

      set_caption_mark(buf, found, cap.kind, cap.bookmark)
    end
  end

  local ref_index = { figure = 1, table = 1 }
  local refs_by_kind = { figure = {}, table = {} }
  for _, ref in ipairs(info.refs) do
    table.insert(refs_by_kind[ref.kind], ref)
  end

  for row, line in ipairs(lines) do
    local zero = row - 1
    for _, kind in ipairs({ "figure", "table" }) do
      local label = kind_label(kind)
      local search_from = 1
      while true do
        local a, b = line:find(label .. "%s+%d+,%s+page%s+%d+", search_from)
        if not a then
          break
        end

        local ref = refs_by_kind[kind][ref_index[kind]]
        if ref then
          set_ref_mark(buf, zero, a - 1, b, kind, ref.bookmark)
          ref_index[kind] = ref_index[kind] + 1
        end
        search_from = b + 1
      end
    end
  end

  M.refresh(buf)

  -- The refresh pass above can rewrite caption rows (for example to normalise
  -- Figure/Table numbering). Re-apply the paragraph style afterwards so a
  -- reopened real Word caption is displayed as Caption rather than Normal.
  local ok_styles, styles = pcall(require, "wordvim.styles")
  if ok_styles and styles and styles.set_paragraph_style then
    for _, item in ipairs(sorted_caption_items(buf)) do
      styles.set_paragraph_style(buf, item.row, "caption")
    end
  end
end

function M.apply_to_docx(docx, buf)
  local s = get_state(buf)
  local captions = s.save_captions or {}
  local refs = s.save_refs or {}

  if vim.tbl_isempty(captions) and vim.tbl_isempty(refs) then
    return true
  end

  local spec_path = vim.fn.tempname() .. ".tsv"
  local spec_lines = {}

  for marker, info in pairs(captions) do
    table.insert(spec_lines, table.concat({
      "CAP",
      marker,
      kind_label(info.kind),
      info.bookmark,
      tostring(info.number or 1),
      tostring(info.page or 1),
      vim.base64.encode(info.title or ""),
    }, "\t"))
  end

  for marker, info in pairs(refs) do
    table.insert(spec_lines, table.concat({
      "REF",
      marker,
      kind_label(info.kind),
      info.bookmark,
      tostring(info.number or 1),
      tostring(info.page or 1),
    }, "\t"))
  end

  table.sort(spec_lines)
  vim.fn.writefile(spec_lines, spec_path)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$specPath = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$xmlNs = 'http://www.w3.org/XML/1998/namespace'

function New-WElement($xml, $name) {
    return $xml.CreateElement('w', $name, $nsUri)
}

function Set-WAttr($node, $name, $value) {
    [void]$node.SetAttribute($name, $nsUri, [string]$value)
}

function New-TextRun($xml, $text, $templateRun) {
    $r = New-WElement $xml 'r'
    if ($null -ne $templateRun) {
        $rPr = $templateRun.SelectSingleNode('w:rPr', $script:ns)
        if ($null -ne $rPr) {
            [void]$r.AppendChild($rPr.CloneNode($true))
        }
    }
    $t = New-WElement $xml 't'
    $attr = $xml.CreateAttribute('xml', 'space', $xmlNs)
    $attr.Value = 'preserve'
    [void]$t.Attributes.Append($attr)
    $t.InnerText = [string]$text
    [void]$r.AppendChild($t)
    return $r
}

function New-FieldCharRun($xml, $kind, $dirty) {
    $r = New-WElement $xml 'r'
    $fld = New-WElement $xml 'fldChar'
    Set-WAttr $fld 'fldCharType' $kind
    if ($dirty) { Set-WAttr $fld 'dirty' 'true' }
    [void]$r.AppendChild($fld)
    return $r
}

function New-InstructionRun($xml, $text) {
    $r = New-WElement $xml 'r'
    $instr = New-WElement $xml 'instrText'
    $attr = $xml.CreateAttribute('xml', 'space', $xmlNs)
    $attr.Value = 'preserve'
    [void]$instr.Attributes.Append($attr)
    $instr.InnerText = [string]$text
    [void]$r.AppendChild($instr)
    return $r
}

function New-ComplexFieldRuns($xml, $instruction, $resultText) {
    return @(
        (New-FieldCharRun $xml 'begin' $true),
        (New-InstructionRun $xml $instruction),
        (New-FieldCharRun $xml 'separate' $false),
        (New-TextRun $xml $resultText $null),
        (New-FieldCharRun $xml 'end' $false)
    )
}

$specs = @()
foreach ($line in Get-Content -LiteralPath $specPath -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split "`t"
    if ($parts[0] -eq 'CAP' -and $parts.Count -ge 7) {
        $title = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[6]))
        $specs += [PSCustomObject]@{
            Type='CAP'; Marker=$parts[1]; Kind=$parts[2]; Bookmark=$parts[3]; Number=[int]$parts[4]; Page=[int]$parts[5]; Title=$title
        }
    }
    elseif ($parts[0] -eq 'REF' -and $parts.Count -ge 6) {
        $specs += [PSCustomObject]@{
            Type='REF'; Marker=$parts[1]; Kind=$parts[2]; Bookmark=$parts[3]; Number=[int]$parts[4]; Page=[int]$parts[5]; Title=''
        }
    }
}

$zipRead = $null
$reader = $null
try {
    $zipRead = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zipRead.GetEntry('word/document.xml')
    if ($null -eq $entry) { throw 'word/document.xml not found' }
    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $zipRead) { $zipRead.Dispose() }
}

$script:ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$script:ns.AddNamespace('w', $nsUri)
$body = $xml.SelectSingleNode('/w:document/w:body', $script:ns)
$bookmarkId = 6000

foreach ($spec in $specs) {
    if ($spec.Type -ne 'CAP') { continue }

    $markerP = $null
    foreach ($p in $body.SelectNodes('w:p', $script:ns)) {
        $parts = @()
        foreach ($t in $p.SelectNodes('.//w:t', $script:ns)) { $parts += $t.InnerText }
        if (($parts -join '') -eq $spec.Marker) {
            $markerP = $p
            break
        }
    }

    if ($null -eq $markerP) {
        throw ('Caption marker not found: ' + $spec.Marker)
    }

    $pPr = $markerP.SelectSingleNode('w:pPr', $script:ns)
    if ($null -eq $pPr) {
        $pPr = New-WElement $xml 'pPr'
        [void]$markerP.PrependChild($pPr)
    }

    $pStyle = $pPr.SelectSingleNode('w:pStyle', $script:ns)
    if ($null -eq $pStyle) {
        $pStyle = New-WElement $xml 'pStyle'
        [void]$pPr.PrependChild($pStyle)
    }
    Set-WAttr $pStyle 'val' 'Caption'

    $children = @($markerP.ChildNodes)
    foreach ($child in $children) {
        if ($child -ne $pPr) { [void]$markerP.RemoveChild($child) }
    }

    $bookmarkId = $bookmarkId + 1
    $bmStart = New-WElement $xml 'bookmarkStart'
    Set-WAttr $bmStart 'id' $bookmarkId
    Set-WAttr $bmStart 'name' $spec.Bookmark
    [void]$markerP.AppendChild($bmStart)

    [void]$markerP.AppendChild((New-TextRun $xml ($spec.Kind + ' ') $null))
    foreach ($r in (New-ComplexFieldRuns $xml (' SEQ ' + $spec.Kind + ' \* ARABIC ') ([string]$spec.Number))) {
        [void]$markerP.AppendChild($r)
    }

    $bmEnd = New-WElement $xml 'bookmarkEnd'
    Set-WAttr $bmEnd 'id' $bookmarkId
    [void]$markerP.AppendChild($bmEnd)

    if (-not [string]::IsNullOrWhiteSpace($spec.Title)) {
        [void]$markerP.AppendChild((New-TextRun $xml (' — ' + $spec.Title) $null))
    }
}

foreach ($spec in $specs) {
    if ($spec.Type -ne 'REF') { continue }

    $done = $false
    foreach ($p in $body.SelectNodes('.//w:p', $script:ns)) {
        $textNodes = @($p.SelectNodes('.//w:t', $script:ns))
        foreach ($t in $textNodes) {
            $text = [string]$t.InnerText
            $idx = $text.IndexOf($spec.Marker)
            if ($idx -lt 0) { continue }

            $run = $t.ParentNode
            $parent = $run.ParentNode
            $before = $text.Substring(0, $idx)
            $afterStart = $idx + $spec.Marker.Length
            $after = ''
            if ($afterStart -lt $text.Length) { $after = $text.Substring($afterStart) }

            if ($before.Length -gt 0) {
                [void]$parent.InsertBefore((New-TextRun $xml $before $run), $run)
            }

            foreach ($r in (New-ComplexFieldRuns $xml (' REF ' + $spec.Bookmark + ' \h ') ($spec.Kind + ' ' + [string]$spec.Number))) {
                [void]$parent.InsertBefore($r, $run)
            }

            [void]$parent.InsertBefore((New-TextRun $xml ', page ' $run), $run)

            foreach ($r in (New-ComplexFieldRuns $xml (' PAGEREF ' + $spec.Bookmark + ' \h ') ([string]$spec.Page))) {
                [void]$parent.InsertBefore($r, $run)
            }

            if ($after.Length -gt 0) {
                [void]$parent.InsertBefore((New-TextRun $xml $after $run), $run)
            }

            [void]$parent.RemoveChild($run)
            $done = $true
            break
        }
        if ($done) { break }
    }

    if (-not $done) {
        throw ('Cross-reference marker not found: ' + $spec.Marker)
    }
}

# Ask Word-compatible editors to update dirty fields when they open the file.
$allText = ''
foreach ($t in $xml.SelectNodes('//w:t', $script:ns)) { $allText += $t.InnerText }
if ($allText.Contains('WORDVIMCAPTIONTOKEN') -or $allText.Contains('WORDVIMXREFTOKEN')) {
    throw 'Caption/reference marker remained in document.xml'
}

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
    if ($null -ne $xmlWriter) { $xmlWriter.Dispose() }
    if ($null -ne $stringWriter) { $stringWriter.Dispose() }
}
$newXml = $stringBuilder.ToString()

$fileStream = $null
$zipUpdate = $null
$writer = $null
try {
    $fileStream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $zipUpdate = New-Object System.IO.Compression.ZipArchive($fileStream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
    $oldEntry = $zipUpdate.GetEntry('word/document.xml')
    $oldEntry.Delete()
    $newEntry = $zipUpdate.CreateEntry('word/document.xml', [System.IO.Compression.CompressionLevel]::Optimal)
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $writer.Write($newXml)
    $writer.Flush()
}
finally {
    if ($null -ne $writer) { $writer.Dispose() }
    if ($null -ne $zipUpdate) { $zipUpdate.Dispose() }
    if ($null -ne $fileStream) { $fileStream.Dispose() }
}

# Basic ZIP-level validation.
$zipCheck = $null
$checkReader = $null
try {
    $zipCheck = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zipCheck.GetEntry('word/document.xml')
    if ($null -eq $entry) { throw 'word/document.xml missing after caption update' }
    $checkReader = New-Object System.IO.StreamReader($entry.Open())
    $checkText = $checkReader.ReadToEnd()
    if ($checkText -notmatch '<w:document') { throw 'Invalid document.xml after caption update' }
    if ($checkText.Contains('WORDVIMCAPTIONTOKEN') -or $checkText.Contains('WORDVIMXREFTOKEN')) {
        throw 'Word Vim marker remained after ZIP update'
    }
}
finally {
    if ($null -ne $checkReader) { $checkReader.Dispose() }
    if ($null -ne $zipCheck) { $zipCheck.Dispose() }
}
]], ps_escape(docx), ps_escape(spec_path))

  local ok, output = run_powershell(script)
  pcall(vim.fn.delete, spec_path)

  if not ok then
    vim.notify("Word Vim: could not create captions/cross-references:\n" .. output, vim.log.levels.ERROR)
    return false
  end

  return true
end

function M.attach(buf)
  vim.keymap.set("n", "<leader>cf", M.insert_figure_caption, {
    buffer = buf, silent = true, desc = "Word Vim: insert Figure caption",
  })
  vim.keymap.set("n", "<leader>ct", M.insert_table_caption, {
    buffer = buf, silent = true, desc = "Word Vim: insert Table caption",
  })
  vim.keymap.set("n", "<leader>rf", M.insert_figure_reference, {
    buffer = buf, silent = true, desc = "Word Vim: insert Figure cross-reference",
  })
  vim.keymap.set("n", "<leader>rt", M.insert_table_reference, {
    buffer = buf, silent = true, desc = "Word Vim: insert Table cross-reference",
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      local s = state[buf]
      if s and not s.updating then
        schedule_refresh(buf)
      end
    end,
  })
end

function M.detach(buf)
  local s = state[buf]
  if s then
    close_picker(buf)
    if s.timer then
      pcall(function()
        s.timer:stop()
        s.timer:close()
      end)
    end
  end
  state[buf] = nil
end

function M.setup()
  vim.api.nvim_create_user_command("WordCaptionFigure", M.insert_figure_caption, {
    desc = "Insert Word Figure caption",
  })
  vim.api.nvim_create_user_command("WordCaptionTable", M.insert_table_caption, {
    desc = "Insert Word Table caption",
  })
  vim.api.nvim_create_user_command("WordRefFigure", M.insert_figure_reference, {
    desc = "Insert Word Figure cross-reference",
  })
  vim.api.nvim_create_user_command("WordRefTable", M.insert_table_reference, {
    desc = "Insert Word Table cross-reference",
  })
end

return M
