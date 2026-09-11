-- ============================================================
-- lua/wordvim/styleui.lua
--
-- LibreOffice-like Word style UI:
--
--   LEFT        DOCUMENT                    RIGHT
--   -----       ------------------------    ----------------------
--    1          paragraph text              1  Normal
--    │          continuation                2  Body Text
--                                           3  Code
--    4          heading                     4  Heading 1
--
-- Commands:
--   :WordStyleUI
--   :WordStyleUIClose
--   :WordStyleUIToggle
--
-- Shortcut:
--   Space w s
--
-- IMPORTANT:
-- This first version is designed for normal paragraphs, headings
-- and list items. Markdown tables are intentionally left for the
-- next stage because each table cell needs its own paragraph/style
-- model.
-- ============================================================

local M = {}

local styles = require("wordvim.styles")
local styleeditor = require("wordvim.styleeditor")

local ns_left = vim.api.nvim_create_namespace("WordVimStyleUILeft")
local ns_right = vim.api.nvim_create_namespace("WordVimStyleUIRight")

local sessions = {}

local LEFT_WIDTH = 5
local RIGHT_WIDTH = 30

-- ------------------------------------------------------------
-- Utility
-- ------------------------------------------------------------

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_docx_buffer(buf)
  return valid_buf(buf) and vim.b[buf].docx_original_file ~= nil
end

local function trim(s)
  return vim.trim(tostring(s or ""))
end

local function line_at(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function is_heading(line)
  return line:match("^#+%s+") ~= nil
end

local function is_bullet(line)
  return line:match("^%s*[-+*]%s+") ~= nil
end

local function is_numbered(line)
  return line:match("^%s*%d+[%.%)]%s+") ~= nil
end

local function is_list_item(line)
  return is_bullet(line) or is_numbered(line)
end

local function is_table_line(line)
  local t = trim(line)
  return t:match("^|.*|$") ~= nil
end

local function ends_hard_break(line)
  return line:match("%s%s$") ~= nil
end

local function get_session_by_any_buffer(buf)
  if sessions[buf] then
    return sessions[buf]
  end

  for _, session in pairs(sessions) do
    if session.left_buf == buf or session.right_buf == buf then
      return session
    end
  end

  return nil
end

-- ------------------------------------------------------------
-- Stable style numbering
-- ------------------------------------------------------------

local function style_priority(name)
  local lower = (name or ""):lower()

  if lower == "normal" then
    return 1
  end

  if lower == "body text" then
    return 2
  end

  if lower == "code" then
    return 3
  end

  local heading = name and name:match("^Heading%s+(%d+)$")
  if heading then
    return 10 + tonumber(heading)
  end

  return 1000
end

local function rebuild_style_numbers(session)
  local cached = styles.get_paragraph_styles(session.doc_buf)

  table.sort(cached, function(a, b)
    local pa = style_priority(a.name)
    local pb = style_priority(b.name)

    if pa ~= pb then
      return pa < pb
    end

    return (a.name or ""):lower() < (b.name or ""):lower()
  end)

  session.number_to_style = {}
  session.style_to_number = {}
  session.style_order = {}

  for index, style in ipairs(cached) do
    session.number_to_style[index] = style.name
    session.style_to_number[(style.name or ""):lower()] = index
    table.insert(session.style_order, style.name)
  end
end

local function style_number(session, style_name)
  return session.style_to_number[(style_name or "Normal"):lower()]
end

-- ------------------------------------------------------------
-- Colors
-- Generate a deterministic unique hue from the style number.
-- ------------------------------------------------------------

local function hue_to_rgb(p, q, t)
  if t < 0 then
    t = t + 1
  end

  if t > 1 then
    t = t - 1
  end

  if t < 1 / 6 then
    return p + (q - p) * 6 * t
  end

  if t < 1 / 2 then
    return q
  end

  if t < 2 / 3 then
    return p + (q - p) * (2 / 3 - t) * 6
  end

  return p
end

local function hsl_to_hex(h, s, l)
  h = h / 360
  s = s / 100
  l = l / 100

  local r
  local g
  local b

  if s == 0 then
    r, g, b = l, l, l
  else
    local q

    if l < 0.5 then
      q = l * (1 + s)
    else
      q = l + s - l * s
    end

    local p = 2 * l - q

    r = hue_to_rgb(p, q, h + 1 / 3)
    g = hue_to_rgb(p, q, h)
    b = hue_to_rgb(p, q, h - 1 / 3)
  end

  return string.format(
    "#%02X%02X%02X",
    math.floor(r * 255 + 0.5),
    math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5)
  )
end

local function luminance(hex)
  local r = tonumber(hex:sub(2, 3), 16) / 255
  local g = tonumber(hex:sub(4, 5), 16) / 255
  local b = tonumber(hex:sub(6, 7), 16) / 255

  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

local function ensure_highlights(session)
  session.highlights = {}

  for number, _ in ipairs(session.style_order) do
    -- Golden-angle distribution gives stable, well-separated hues.
    local hue = ((number - 1) * 137.508) % 360
    local bg = hsl_to_hex(hue, 58, 34)
    local fg = luminance(bg) > 0.45 and "#101010" or "#FFFFFF"

    local group = "WordVimStyleColor" .. tostring(number)

    vim.api.nvim_set_hl(0, group, {
      fg = fg,
      bg = bg,
      bold = true,
    })

    session.highlights[number] = group
  end

  vim.api.nvim_set_hl(0, "WordVimStyleCurrent", {
    bold = true,
    underline = true,
  })

  vim.api.nvim_set_hl(0, "WordVimStyleMuted", {
    italic = true,
  })
end

-- ------------------------------------------------------------
-- Paragraph model
--
-- Returns arrays indexed by source row (0-based):
--   paragraph_start[row] = start row of logical paragraph
--   paragraph_style[row] = effective style name
--
-- A Shift+Enter hard break is represented by two trailing spaces,
-- therefore the following line remains in the same paragraph.
--
-- Each list item is treated as its own paragraph.
-- ------------------------------------------------------------

local function build_paragraph_model(session)
  local buf = session.doc_buf
  local count = vim.api.nvim_buf_line_count(buf)

  local paragraph_start = {}
  local paragraph_style = {}

  local current_start = nil
  local current_style = nil

  for row = 0, count - 1 do
    local line = line_at(buf, row)
    local prev = row > 0 and line_at(buf, row - 1) or ""

    if is_blank(line) then
      current_start = nil
      current_style = nil

    elseif row > 0 and ends_hard_break(prev) and current_start ~= nil then
      -- Shift+Enter: this editor row is still part of the SAME
      -- Word paragraph, so it gets the same color but no number.
      paragraph_start[row] = current_start
      paragraph_style[row] = current_style

    else
      -- In the compact Word Vim editor every ordinary visible row
      -- represents the START of a new Word paragraph.
      --
      -- The only exception is a row following a Shift+Enter hard
      -- break, handled above.
      current_start = row
      current_style = styles.get_effective_paragraph_style(buf, row)

      paragraph_start[row] = row
      paragraph_style[row] = current_style
    end
  end

  session.paragraph_start = paragraph_start
  session.paragraph_style = paragraph_style
end

-- ------------------------------------------------------------
-- Left gutter
-- ------------------------------------------------------------

local function screen_height_for_row(session, row)
  if not valid_win(session.doc_win) then
    return 1
  end

  local ok, height = pcall(
    vim.api.nvim_win_text_height,
    session.doc_win,
    {
      start_row = row,
      end_row = row,
    }
  )

  if
    ok
    and type(height) == "table"
    and tonumber(height.all)
    and height.all > 0
  then
    return height.all
  end

  return 1
end

local function render_left(session)
  if not valid_buf(session.left_buf) then
    return
  end

  build_paragraph_model(session)

  local count = vim.api.nvim_buf_line_count(session.doc_buf)
  local lines = {}
  local gutter_to_docrow = {}
  local docrow_to_gutter = {}
  local row_colors = {}

  local gutter_row = 0

  for row = 0, count - 1 do
    local line = line_at(session.doc_buf, row)
    local height = screen_height_for_row(session, row)

    docrow_to_gutter[row] = gutter_row

    local style_name = session.paragraph_style[row] or "Normal"
    local number = style_number(session, style_name)
    local group = number and session.highlights[number]

    for visual_part = 1, height do
      local value = ""

      if
        not is_blank(line)
        and visual_part == 1
        and session.paragraph_start[row] == row
      then
        value = number and tostring(number) or "?"
      end

      table.insert(lines, value)
      gutter_to_docrow[gutter_row] = row
      row_colors[gutter_row] = group
      gutter_row = gutter_row + 1
    end
  end

  session.gutter_to_docrow = gutter_to_docrow
  session.docrow_to_gutter = docrow_to_gutter

  vim.bo[session.left_buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    session.left_buf,
    0,
    -1,
    false,
    lines
  )
  vim.bo[session.left_buf].modifiable = true
  vim.bo[session.left_buf].modified = false

  vim.api.nvim_buf_clear_namespace(
    session.left_buf,
    ns_left,
    0,
    -1
  )

  for row = 0, #lines - 1 do
    local group = row_colors[row]

    if group then
      vim.api.nvim_buf_set_extmark(
        session.left_buf,
        ns_left,
        row,
        0,
        {
          line_hl_group = group,
          priority = 100,
        }
      )
    end
  end
end

local function parse_number(line)
  local number = trim(line):match("^(%d+)$")
  return number and tonumber(number) or nil
end

local function apply_left_change(session)
  if session.rendering or not valid_buf(session.left_buf) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(session.left_win)
  local gutter_row = cursor[1] - 1
  local row = session.gutter_to_docrow
    and session.gutter_to_docrow[gutter_row]
    or nil

  if row == nil then
    render_left(session)
    return
  end

  local source_line = line_at(session.doc_buf, row)

  if is_blank(source_line) then
    render_left(session)
    return
  end

  local start = session.paragraph_start[row]

  if start ~= row then
    vim.notify(
      "Word Vim: style number can be changed only at paragraph start",
      vim.log.levels.WARN
    )
    render_left(session)
    return
  end

  local first_gutter_row = session.docrow_to_gutter
    and session.docrow_to_gutter[row]
    or gutter_row

  if gutter_row ~= first_gutter_row then
    vim.notify(
      "Word Vim: style number can be changed only at paragraph start",
      vim.log.levels.WARN
    )
    render_left(session)
    return
  end

  local edited = line_at(session.left_buf, gutter_row)
  local number = parse_number(edited)

  if not number then
    vim.notify(
      "Word Vim: enter a style number from the right panel",
      vim.log.levels.WARN
    )
    render_left(session)
    return
  end

  local style_name = session.number_to_style[number]

  if not style_name then
    vim.notify(
      "Word Vim: no style with number " .. number,
      vim.log.levels.ERROR
    )
    render_left(session)
    return
  end

  styles.apply_style_to_row(
    session.doc_buf,
    start,
    style_name
  )

  session.rendering = true
  render_left(session)
  session.rendering = false

  vim.notify(
    "Word Vim: paragraph style -> "
      .. number
      .. " "
      .. style_name,
    vim.log.levels.INFO
  )
end

-- ------------------------------------------------------------
-- Right style list
-- ------------------------------------------------------------

local function effective_style_at_cursor(session)
  if not valid_win(session.doc_win) then
    return "Normal"
  end

  local row = vim.api.nvim_win_get_cursor(session.doc_win)[1] - 1
  local start = session.paragraph_start[row] or row

  return session.paragraph_style[start]
    or styles.get_effective_paragraph_style(session.doc_buf, start)
end

local function render_right(session)
  if not valid_buf(session.right_buf) then
    return
  end

  local active_style = effective_style_at_cursor(session)
  local lines = {}

  for number, name in ipairs(session.style_order) do
    local prefix = (name == active_style) and "> " or "  "
    lines[number] = string.format(
      "%s%2d  %s",
      prefix,
      number,
      name
    )
  end

  vim.bo[session.right_buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    session.right_buf,
    0,
    -1,
    false,
    lines
  )
  vim.bo[session.right_buf].modifiable = false
  vim.bo[session.right_buf].modified = false

  vim.api.nvim_buf_clear_namespace(
    session.right_buf,
    ns_right,
    0,
    -1
  )

  for number, _ in ipairs(session.style_order) do
    local group = session.highlights[number]

    if group then
      -- Highlight only the numeric field.
      vim.api.nvim_buf_add_highlight(
        session.right_buf,
        ns_right,
        group,
        number - 1,
        2,
        6
      )
    end

    if session.style_order[number] == active_style then
      vim.api.nvim_buf_add_highlight(
        session.right_buf,
        ns_right,
        "WordVimStyleCurrent",
        number - 1,
        0,
        -1
      )
    end
  end
end

local function refresh(session)
  if not session or session.rendering then
    return
  end

  if not is_docx_buffer(session.doc_buf) then
    return
  end

  session.rendering = true

  rebuild_style_numbers(session)
  ensure_highlights(session)
  render_left(session)
  render_right(session)

  session.rendering = false
end

-- ------------------------------------------------------------
-- Window synchronization
-- ------------------------------------------------------------

local function sync_left_view(session)
  if
    not valid_win(session.doc_win)
    or not valid_win(session.left_win)
  then
    return
  end

  local ok_doc, doc_view = pcall(function()
    return vim.api.nvim_win_call(
      session.doc_win,
      function()
        return vim.fn.winsaveview()
      end
    )
  end)

  if not ok_doc or not doc_view then
    return
  end

  local doc_cursor = vim.api.nvim_win_get_cursor(session.doc_win)
  local doc_row = doc_cursor[1] - 1

  local gutter_cursor =
    session.docrow_to_gutter
    and session.docrow_to_gutter[doc_row]
    or doc_row

  local top_doc_row = math.max(0, (doc_view.topline or 1) - 1)

  local gutter_top =
    session.docrow_to_gutter
    and session.docrow_to_gutter[top_doc_row]
    or top_doc_row

  local left_count = vim.api.nvim_buf_line_count(session.left_buf)

  if left_count == 0 then
    return
  end

  gutter_cursor = math.max(
    0,
    math.min(gutter_cursor, left_count - 1)
  )

  gutter_top = math.max(
    0,
    math.min(gutter_top, left_count - 1)
  )

  pcall(
    vim.api.nvim_win_set_cursor,
    session.left_win,
    { gutter_cursor + 1, 0 }
  )

  pcall(function()
    vim.api.nvim_win_call(
      session.left_win,
      function()
        vim.fn.winrestview({
          topline = gutter_top + 1,
          topfill = 0,
          leftcol = 0,
          skipcol = 0,
        })
      end
    )
  end)
end

local function sync_document_from_left(session)
  if
    not valid_win(session.doc_win)
    or not valid_win(session.left_win)
  then
    return
  end

  local left_cursor = vim.api.nvim_win_get_cursor(session.left_win)
  local gutter_row = left_cursor[1] - 1

  local row = session.gutter_to_docrow
    and session.gutter_to_docrow[gutter_row]
    or gutter_row

  local doc_count = vim.api.nvim_buf_line_count(session.doc_buf)

  if doc_count == 0 then
    return
  end

  row = math.max(0, math.min(row, doc_count - 1))

  pcall(
    vim.api.nvim_win_set_cursor,
    session.doc_win,
    { row + 1, 0 }
  )

  sync_left_view(session)
end

local function refresh_active_style(session)
  if not session then
    return
  end

  build_paragraph_model(session)
  sync_left_view(session)
  render_right(session)
end


local function open_selected_style_editor(session)
  if
    not session
    or not valid_win(session.right_win)
    or not valid_buf(session.right_buf)
  then
    return
  end

  local row = vim.api.nvim_win_get_cursor(session.right_win)[1]
  local style_name = session.style_order[row]

  if not style_name then
    vim.notify(
      "Word Vim: no style on this row",
      vim.log.levels.WARN
    )
    return
  end

  styleeditor.open(
    session.doc_buf,
    style_name,
    function()
      local current = sessions[session.doc_buf]
      if current then
        refresh(current)
      end
    end
  )
end

-- ------------------------------------------------------------
-- Open / close
-- ------------------------------------------------------------

local function configure_side_buffer(buf, filetype)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].filetype = filetype
end

local function configure_left_window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].scrollbind = false
  vim.wo[win].winfixwidth = true
end

local function configure_right_window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].winfixwidth = true
end

function M.close(doc_buf)
  local session = sessions[doc_buf]

  if not session then
    return
  end

  if valid_win(session.left_win) then
    pcall(vim.api.nvim_win_close, session.left_win, true)
  end

  if valid_win(session.right_win) then
    pcall(vim.api.nvim_win_close, session.right_win, true)
  end

  if valid_win(session.doc_win) then
    if session.old_wrap ~= nil then
      vim.wo[session.doc_win].wrap = session.old_wrap
    end

    if session.old_linebreak ~= nil then
      vim.wo[session.doc_win].linebreak = session.old_linebreak
    end

    if session.old_breakindent ~= nil then
      vim.wo[session.doc_win].breakindent = session.old_breakindent
    end

    if session.old_smoothscroll ~= nil then
      vim.wo[session.doc_win].smoothscroll = session.old_smoothscroll
    end

    if session.old_scrollbind ~= nil then
      vim.wo[session.doc_win].scrollbind = session.old_scrollbind
    end
  end

  sessions[doc_buf] = nil
end

function M.open(doc_buf)
  doc_buf = doc_buf or vim.api.nvim_get_current_buf()

  if not is_docx_buffer(doc_buf) then
    vim.notify(
      "Word Vim: open a DOCX document first",
      vim.log.levels.WARN
    )
    return
  end

  if sessions[doc_buf] then
    local existing = sessions[doc_buf]

    if valid_win(existing.left_win) and valid_win(existing.right_win) then
      refresh(existing)
      return
    end

    M.close(doc_buf)
  end

  local doc_win = vim.fn.bufwinid(doc_buf)

  if doc_win == -1 then
    vim.notify(
      "Word Vim: DOCX buffer is not visible",
      vim.log.levels.ERROR
    )
    return
  end

  local session = {
    doc_buf = doc_buf,
    doc_win = doc_win,
    rendering = false,
    old_wrap = vim.wo[doc_win].wrap,
    old_linebreak = vim.wo[doc_win].linebreak,
    old_breakindent = vim.wo[doc_win].breakindent,
    old_smoothscroll = vim.wo[doc_win].smoothscroll,
    old_scrollbind = vim.wo[doc_win].scrollbind,
  }

  sessions[doc_buf] = session

  -- Long document lines remain readable while the side panels
  -- are open. The left style gutter is expanded to the exact
  -- screen height of every wrapped document line.
  vim.wo[doc_win].wrap = true
  vim.wo[doc_win].linebreak = true
  vim.wo[doc_win].breakindent = true
  vim.wo[doc_win].smoothscroll = false
  vim.wo[doc_win].scrollbind = false

  -- LEFT
  vim.api.nvim_set_current_win(doc_win)
  vim.cmd("leftabove " .. LEFT_WIDTH .. "vnew")

  session.left_win = vim.api.nvim_get_current_win()
  session.left_buf = vim.api.nvim_get_current_buf()

  configure_side_buffer(session.left_buf, "wordvimstylegutter")
  configure_left_window(session.left_win)

  -- RIGHT
  vim.api.nvim_set_current_win(doc_win)
  vim.cmd("rightbelow " .. RIGHT_WIDTH .. "vnew")

  session.right_win = vim.api.nvim_get_current_win()
  session.right_buf = vim.api.nvim_get_current_buf()

  configure_side_buffer(session.right_buf, "wordvimstyles")
  configure_right_window(session.right_win)

  vim.api.nvim_buf_set_name(
    session.left_buf,
    "WordVim://StyleGutter/" .. doc_buf
  )

  vim.api.nvim_buf_set_name(
    session.right_buf,
    "WordVim://Styles/" .. doc_buf
  )

  -- Space+w+s must behave as a real toggle from all three panes.
  -- This is especially important after focus moves into the left/right
  -- style panels: the document-local mapping is not active there.
  for _, side_buf in ipairs({ session.left_buf, session.right_buf }) do
    vim.keymap.set("n", "<leader>ws", function()
      M.toggle()
    end, {
      buffer = side_buf,
      silent = true,
      desc = "Word Vim: toggle style UI",
    })
  end

  -- Open settings for the style under the cursor.
  vim.keymap.set("n", "<CR>", function()
    local current = sessions[doc_buf]
    if current then
      open_selected_style_editor(current)
    end
  end, {
    buffer = session.right_buf,
    silent = true,
    desc = "Word Vim: edit selected style",
  })

  vim.keymap.set("n", "e", function()
    local current = sessions[doc_buf]
    if current then
      open_selected_style_editor(current)
    end
  end, {
    buffer = session.right_buf,
    silent = true,
    desc = "Word Vim: edit selected style",
  })

  rebuild_style_numbers(session)
  ensure_highlights(session)
  build_paragraph_model(session)
  render_left(session)
  render_right(session)

  -- Edit a number in the left panel, press Esc, style changes.
  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = session.left_buf,
    callback = function()
      local current = sessions[doc_buf]

      if current then
        apply_left_change(current)
      end
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = session.left_buf,
    callback = function()
      local current = sessions[doc_buf]

      if current and not current.rendering then
        sync_document_from_left(current)
        render_right(current)
      end
    end,
  })

  -- Make changing a number fast: `cc2<Esc>`, `cw2<Esc>`, etc.
  vim.keymap.set("n", "<CR>", function()
    vim.cmd("startinsert")
  end, {
    buffer = session.left_buf,
    silent = true,
    desc = "Word Vim: edit style number",
  })

  -- Keep document and left gutter aligned.
  sync_left_view(session)

  vim.api.nvim_set_current_win(doc_win)

  vim.notify(
    "Word Vim Style UI: Space+w+s closes both panels",
    vim.log.levels.INFO
  )
end

function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  local session = get_session_by_any_buffer(buf)

  if session then
    local doc_buf = session.doc_buf

    if valid_win(session.left_win) or valid_win(session.right_win) then
      M.close(doc_buf)

      if valid_win(session.doc_win) then
        vim.api.nvim_set_current_win(session.doc_win)
      end

      return
    end
  end

  if is_docx_buffer(buf) then
    M.open(buf)
    return
  end

  -- If the command is run from another normal window, try the
  -- visible DOCX buffer in the current tab.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local candidate = vim.api.nvim_win_get_buf(win)

    if is_docx_buffer(candidate) then
      M.open(candidate)
      return
    end
  end

  vim.notify(
    "Word Vim: no visible DOCX document",
    vim.log.levels.WARN
  )
end

-- ------------------------------------------------------------
-- Setup
-- ------------------------------------------------------------


function M.attach(buf)
  vim.keymap.set(
    "n",
    "<leader>ws",
    function()
      M.toggle()
    end,
    {
      buffer = buf,
      silent = true,
      desc = "Word Vim: toggle style UI",
    }
  )
end

function M.setup()
  vim.api.nvim_create_user_command(
    "WordStyleUI",
    function()
      M.open(vim.api.nvim_get_current_buf())
    end,
    {
      desc = "Open Word Vim style gutter and style list",
    }
  )

  vim.api.nvim_create_user_command(
    "WordStyleUIClose",
    function()
      local session = get_session_by_any_buffer(
        vim.api.nvim_get_current_buf()
      )

      if session then
        local doc_win = session.doc_win
        M.close(session.doc_buf)

        if valid_win(doc_win) then
          vim.api.nvim_set_current_win(doc_win)
        end
      end
    end,
    {
      desc = "Close Word Vim style panels",
    }
  )

  vim.api.nvim_create_user_command(
    "WordStyleUIToggle",
    function()
      M.toggle()
    end,
    {
      desc = "Toggle Word Vim style panels",
    }
  )

  local group = vim.api.nvim_create_augroup(
    "WordVimStyleUI",
    { clear = true }
  )

  vim.api.nvim_create_autocmd(
    {
      "CursorMoved",
      "CursorMovedI",
    },
    {
      group = group,
      callback = function(args)
        local session = sessions[args.buf]

        if session then
          refresh_active_style(session)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "WinResized",
    {
      group = group,
      callback = function()
        for _, session in pairs(sessions) do
          if
            valid_win(session.doc_win)
            and valid_win(session.left_win)
          then
            refresh(session)
            sync_left_view(session)
          end
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "WinScrolled",
    {
      group = group,
      callback = function(args)
        local win = tonumber(args.match)

        for _, session in pairs(sessions) do
          if session.doc_win == win then
            sync_left_view(session)
            break
          end
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    {
      "TextChanged",
      "TextChangedI",
    },
    {
      group = group,
      callback = function(args)
        local session = sessions[args.buf]

        if session then
          refresh(session)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "User",
    {
      group = group,
      pattern = "WordVimStyleChanged",
      callback = function(args)
        local buf = args.data and args.data.buf or nil
        local session = buf and sessions[buf] or nil

        if session then
          refresh(session)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "User",
    {
      group = group,
      pattern = "WordVimIndentChanged",
      callback = function(args)
        local buf = args.data and args.data.buf or nil

        -- An indent change can originate from an Insert-mode
        -- expression mapping. During that callback Neovim has a
        -- textlock and does not allow render_left() to rewrite the
        -- side buffer (E565). Refresh on the next event-loop tick.
        vim.schedule(function()
          local session = buf and sessions[buf] or nil

          if session then
            refresh(session)
            sync_left_view(session)
          end
        end)
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "User",
    {
      group = group,
      pattern = "WordVimStyleDefinitionChanged",
      callback = function(args)
        local buf = args.data and args.data.buf or nil
        local session = buf and sessions[buf] or nil

        if session then
          refresh(session)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "BufWipeout",
    {
      group = group,
      pattern = "*.docx",
      callback = function(args)
        M.close(args.buf)
      end,
    }
  )
end

return M
