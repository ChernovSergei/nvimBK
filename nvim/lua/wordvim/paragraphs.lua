-- ============================================================
-- lua/wordvim/paragraphs.lua
--
-- Word-like paragraph behavior for DOCX buffers.
--
-- v6.13 invariant:
--   every REAL editor paragraph has explicit paragraph-style metadata.
--   New paragraphs created with Enter / o / O start as Normal.
--   Shift+Enter remains a line break inside the same Word paragraph.
-- ============================================================

local M = {}

local indents = require("wordvim.indents")
local styles = require("wordvim.styles")

local attached = {}
local augroups = {}

local function is_wordvim_docx(buf)
  return vim.b[buf].docx_original_file ~= nil
end

local function notify_style_changed(buf, row, style)
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WordVimStyleChanged",
    modeline = false,
    data = {
      buf = buf,
      row = row,
      style = style or "Normal",
    },
  })
end

local function set_new_normal(buf, row, copy_indent_from)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local count = vim.api.nvim_buf_line_count(buf)
  if count <= 0 then
    return
  end

  row = math.max(0, math.min(row, count - 1))

  if copy_indent_from ~= nil then
    local source = math.max(0, math.min(copy_indent_from, count - 1))
    indents.copy_indent(buf, source, row)
  end

  styles.set_new_paragraph_normal(buf, row)
  notify_style_changed(buf, row, "Normal")
end

local function schedule_style_repair(buf)
  if vim.b[buf].wordvim_style_repair_pending then
    return
  end

  vim.b[buf].wordvim_style_repair_pending = true

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    vim.b[buf].wordvim_style_repair_pending = false

    if not is_wordvim_docx(buf) then
      return
    end

    if styles.ensure_explicit_styles(buf) then
      notify_style_changed(buf, vim.api.nvim_win_get_cursor(0)[1] - 1)
    end
  end)
end

function M.attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not is_wordvim_docx(buf) then
    return
  end

  if attached[buf] then
    return
  end

  attached[buf] = true

  -- Make imported Normal paragraphs explicit immediately.  This is harmless
  -- when docx.lua already performed the same pass and protects callers that
  -- attach this module independently.
  styles.ensure_explicit_styles(buf)

  -- Enter: split the current paragraph, but the NEW Word paragraph starts as
  -- Normal.  The original paragraph keeps its existing style extmark.
  vim.keymap.set("i", "<CR>", function()
    local old_row = vim.api.nvim_win_get_cursor(0)[1] - 1

    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local new_row = math.min(old_row + 1, vim.api.nvim_buf_line_count(buf) - 1)
        set_new_normal(buf, new_row, old_row)
      end
    end)

    return "<CR>"
  end, {
    buffer = buf,
    expr = true,
    noremap = true,
    silent = true,
    desc = "Word Vim: new Normal Word paragraph",
  })

  -- Normal-mode o: native Vim open-below, then explicitly mark the new row as
  -- Normal.  Existing style extmarks below it follow their original paragraph.
  vim.keymap.set("n", "o", function()
    local old_row = vim.api.nvim_win_get_cursor(0)[1] - 1
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local new_row = math.min(old_row + 1, vim.api.nvim_buf_line_count(buf) - 1)
        set_new_normal(buf, new_row, old_row)
      end
    end)
    return "o"
  end, {
    buffer = buf,
    expr = true,
    noremap = true,
    silent = true,
    desc = "Word Vim: open Normal paragraph below",
  })

  -- Normal-mode O: the original paragraph moves down; right_gravity=true keeps
  -- its style attached to it.  The new row above is explicitly Normal.
  vim.keymap.set("n", "O", function()
    local old_row = vim.api.nvim_win_get_cursor(0)[1] - 1
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        set_new_normal(buf, old_row, math.min(old_row + 1, vim.api.nvim_buf_line_count(buf) - 1))
      end
    end)
    return "O"
  end, {
    buffer = buf,
    expr = true,
    noremap = true,
    silent = true,
    desc = "Word Vim: open Normal paragraph above",
  })

  -- Shift+Enter: hard line break INSIDE the same Word paragraph.  No separate
  -- style marker is created for the continuation row.
  vim.keymap.set("i", "<S-CR>", "  <CR>", {
    buffer = buf,
    noremap = true,
    silent = true,
    desc = "Word Vim: line break inside paragraph",
  })

  local group = vim.api.nvim_create_augroup("WordVimParagraphs_" .. tostring(buf), { clear = true })
  augroups[buf] = group

  -- Covers paste, :put, deletions and other edits that do not go through our
  -- Enter/o/O mappings.  Run after textlock has ended; only missing paragraph
  -- style markers are filled, existing Word styles are preserved.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    buffer = buf,
    callback = function()
      schedule_style_repair(buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      attached[buf] = nil
      augroups[buf] = nil
    end,
  })
end

function M.detach(buf)
  attached[buf] = nil
  local group = augroups[buf]
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    augroups[buf] = nil
  end
end

function M.setup()
end

return M
