-- ============================================================
-- lua/wordvim/styleeditor.lua
--
-- Floating editor for Word paragraph style settings.
--
-- Open from the RIGHT style panel:
--   Enter
--   e
--
-- Popup controls:
--   i / a      edit values
--   Ctrl+S     save changes to Word Vim and close
--   q          close without saving
--   Esc        close without saving (Normal mode)
--
-- The DOCX itself is still written by :w in the main document.
-- ============================================================

local M = {}

local styles = require("wordvim.styles")

local active = nil

local FIELD_ROWS = {
  based_on = 5,
  font = 6,
  size = 7,
  bold = 8,
  italic = 9,
  underline = 10,
  color = 11,
  alignment = 12,
  before = 13,
  after = 14,
  panel_color = 15,
}

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function bool_text(v)
  v = tostring(v or ""):lower()
  if v == "yes" or v == "true" or v == "1" or v == "on" then
    return "yes"
  end
  return "no"
end

local function field_line(label, value)
  return string.format("%-20s = %s", label, tostring(value or ""))
end

local function value_from_line(line)
  return (line:match("=%s*(.*)$") or ""):gsub("%s+$", "")
end

local function close_popup()
  if not active then
    return
  end

  -- Save the current popup state locally and clear `active`
  -- BEFORE closing the window. Because the popup buffer uses
  -- bufhidden=wipe, closing the window can trigger BufWipeout,
  -- whose callback also clears `active`.
  --
  -- In the old version that made `active` become nil between
  -- closing the window and deleting the buffer, causing:
  --
  --   attempt to index upvalue 'active' (a nil value)
  local popup = active
  active = nil

  if valid_win(popup.win) then
    pcall(vim.api.nvim_win_close, popup.win, true)
  end

  if valid_buf(popup.buf) then
    pcall(vim.api.nvim_buf_delete, popup.buf, { force = true })
  end
end

local function render(style)
  return {
    " Word Vim - Style Settings ",
    "",
    "Style                = " .. (style.name or ""),
    "Type                 = " .. (style.type or ""),
    field_line("Based on", style.based_on or ""),
    field_line("Font", style.font or ""),
    field_line("Size pt", style.size or ""),
    field_line("Bold (yes/no)", style.bold or "no"),
    field_line("Italic (yes/no)", style.italic or "no"),
    field_line("Underline (yes/no)", style.underline or "no"),
    field_line("Color HEX", style.color or ""),
    field_line("Alignment", style.alignment or ""),
    field_line("Space before pt", style.before or ""),
    field_line("Space after pt", style.after or ""),
    field_line("Panel color HEX", style.panel_color or ""),
    " Ctrl+S = Save     q / Esc = Cancel ",
    " Values may be blank to inherit/remove direct style property. ",
  }
end

local function protect_prefixes(buf)
  local ns = vim.api.nvim_create_namespace("WordVimStyleEditor")

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- Neovim 0.12 does not accept end_col = -1 in
  -- nvim_buf_set_extmark(). Use whole-line highlights instead.
  --
  -- Title and read-only metadata.
  for row = 0, 3 do
    vim.api.nvim_buf_add_highlight(
      buf,
      ns,
      "Comment",
      row,
      0,
      -1
    )
  end

  -- Footer.
  for row = 15, 16 do
    vim.api.nvim_buf_add_highlight(
      buf,
      ns,
      "Comment",
      row,
      0,
      -1
    )
  end
end

local function parse_fields(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local function at(row)
    return lines[row] or ""
  end

  return {
    based_on = value_from_line(at(FIELD_ROWS.based_on)),
    font = value_from_line(at(FIELD_ROWS.font)),
    size = value_from_line(at(FIELD_ROWS.size)),
    bold = value_from_line(at(FIELD_ROWS.bold)),
    italic = value_from_line(at(FIELD_ROWS.italic)),
    underline = value_from_line(at(FIELD_ROWS.underline)),
    color = value_from_line(at(FIELD_ROWS.color)),
    alignment = value_from_line(at(FIELD_ROWS.alignment)),
    before = value_from_line(at(FIELD_ROWS.before)),
    after = value_from_line(at(FIELD_ROWS.after)),
    panel_color = value_from_line(at(FIELD_ROWS.panel_color)),
  }
end

local function save()
  if not active then
    return
  end

  local values = parse_fields(active.buf)

  local panel = vim.trim(values.panel_color):gsub("^#", "")
  if panel ~= "" and not panel:match("^%x%x%x%x%x%x$") then
    vim.notify("Panel color: use six HEX digits or blank", vim.log.levels.ERROR)
    return
  end
  local document_changed = false
  for field,value in pairs(values) do
    if field ~= "panel_color" and value ~= active.initial_values[field] then
      document_changed = true
    end
  end
  if document_changed then
    local ok, err = styles.update_style_definition(active.doc_buf, active.style_name, values)
    if not ok then
      vim.notify("Word Vim: style settings were not saved:\n" .. tostring(err), vim.log.levels.ERROR)
      return
    end
  end

  local saved, panel_err = require("wordvim.panelcolors").set(active.doc_buf, active.style_name, panel)
  if not saved then
    vim.notify("Panel color was not saved: " .. tostring(panel_err), vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_exec_autocmds("User", {
    pattern = "WordVimStyleDefinitionChanged", modeline = false,
    data = {buf = active.doc_buf, style = active.style_name},
  })
  local name = active.style_name
  local on_saved = active.on_saved

  close_popup()

  if on_saved then
    pcall(on_saved)
  end

  vim.notify(
    document_changed and ("Word Vim: style '" .. name .. "' changed. Use :w to save DOCX.")
      or ("Word Vim: application panel color saved for '" .. name .. "'."),
    vim.log.levels.INFO
  )
end

local function keep_cursor_in_values(win)
  if not active or not valid_win(win) then
    return
  end

  local row = vim.api.nvim_win_get_cursor(win)[1]

  if row < FIELD_ROWS.based_on then
    vim.api.nvim_win_set_cursor(win, { FIELD_ROWS.based_on, 23 })
  elseif row > FIELD_ROWS.panel_color then
    vim.api.nvim_win_set_cursor(win, { FIELD_ROWS.panel_color, 23 })
  end
end

function M.open(doc_buf, style_name, on_saved)
  if active then
    close_popup()
  end

  local style = styles.find_style(doc_buf, style_name)

  if not style then
    vim.notify(
      "Word Vim: style not found: " .. tostring(style_name),
      vim.log.levels.ERROR
    )
    return
  end

  style = vim.deepcopy(style)
  style.panel_color = require("wordvim.panelcolors").get(doc_buf, style_name)

  local width = math.min(76, math.max(58, vim.o.columns - 10))
  local height = 17

  local row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(1, math.floor((vim.o.columns - width) / 2))

  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].filetype = "wordvimstyleeditor"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Style: " .. (style.name or "") .. " ",
    title_pos = "center",
  })

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  active = {
    buf = buf,
    win = win,
    doc_buf = doc_buf,
    style_name = style_name,
    on_saved = on_saved,
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, render(style))
  vim.bo[buf].modified = false
  active.initial_values = parse_fields(buf)

  protect_prefixes(buf)

  -- Start on the first editable field.
  vim.api.nvim_win_set_cursor(win, { FIELD_ROWS.based_on, 23 })

  vim.keymap.set("n", "<C-s>", save, {
    buffer = buf,
    silent = true,
    desc = "Word Vim: save style settings",
  })

  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    save()
  end, {
    buffer = buf,
    silent = true,
    desc = "Word Vim: save style settings",
  })

  vim.keymap.set("n", "q", close_popup, {
    buffer = buf,
    silent = true,
    desc = "Word Vim: cancel style settings",
  })

  vim.keymap.set("n", "<Esc>", close_popup, {
    buffer = buf,
    silent = true,
    desc = "Word Vim: cancel style settings",
  })

  vim.keymap.set("n", "<CR>", function()
    if vim.api.nvim_win_get_cursor(win)[1] == FIELD_ROWS.panel_color then
      local popup = active
      local palette = {"Automatic", "1F4E79 Blue", "548235 Green", "C65911 Orange", "7030A0 Purple", "C00000 Red", "FFD966 Yellow", "404040 Gray", "Custom HEX"}
      local function put(value)
        if active ~= popup or not valid_buf(buf) then return end
        vim.api.nvim_buf_set_lines(buf, FIELD_ROWS.panel_color-1, FIELD_ROWS.panel_color, false, {field_line("Panel color HEX", value)})
      end
      vim.ui.select(palette, {prompt="Application color (all documents):"}, function(choice)
        if not choice then return end
        if choice == "Custom HEX" then
          vim.ui.input({prompt="HEX (blank = automatic): "}, function(value) if value then put(value) end end)
        else put(choice == "Automatic" and "" or choice:sub(1,6)) end
      end)
      return
    end
    vim.cmd("startinsert")
  end, {
    buffer = buf,
    silent = true,
    desc = "Word Vim: edit current style field",
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if active and active.buf == buf then
        keep_cursor_in_values(win)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if active and active.buf == buf then
        active = nil
      end
    end,
  })
end

function M.close()
  close_popup()
end

return M
