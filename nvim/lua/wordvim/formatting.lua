-- ============================================================
-- lua/wordvim/formatting.lua
-- ============================================================

local M = {}

local function escape_visual()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
end

local function wrap_visual(prefix, suffix)
  local buffer = vim.api.nvim_get_current_buf()
  local visual = vim.fn.getpos("v")
  local cursor = vim.api.nvim_win_get_cursor(0)

  local visual_line = visual[2]
  local visual_col = visual[3] - 1
  local cursor_line = cursor[1]
  local cursor_col = cursor[2]

  if visual_line ~= cursor_line then
    vim.notify(
      "Word Vim: formatting currently supports one line at a time",
      vim.log.levels.WARN
    )
    return
  end

  local line = vim.api.nvim_get_current_line()
  local line_length = #line

  local start_col
  local end_col

  if visual_col <= cursor_col then
    start_col = visual_col
    end_col = cursor_col + 1
  else
    start_col = cursor_col
    end_col = visual_col + 1
  end

  start_col = math.max(0, math.min(start_col, line_length))
  end_col = math.max(0, math.min(end_col, line_length))

  if start_col >= end_col then
    return
  end

  local selected = vim.api.nvim_buf_get_text(
    buffer,
    visual_line - 1,
    start_col,
    visual_line - 1,
    end_col,
    {}
  )

  if #selected == 0 then
    return
  end

  vim.api.nvim_buf_set_text(
    buffer,
    visual_line - 1,
    start_col,
    visual_line - 1,
    end_col,
    { prefix .. selected[1] .. suffix }
  )

  escape_visual()
end

local function set_heading(level)
  local buffer = vim.api.nvim_get_current_buf()
  local line = vim.fn.getline(".")
  line = line:gsub("^#+%s*", "")
  vim.fn.setline(".", string.rep("#", level) .. " " .. line)

  -- Keep explicit paragraph-style metadata in sync with the visible Markdown
  -- heading marker.  The save pipeline still emits native Markdown headings,
  -- but the hidden style mark is needed by the gutter/style UI and survives
  -- o/O/Enter/extmark operations reliably.
  local ok, styles = pcall(require, "wordvim.styles")
  if ok then
    styles.set_paragraph_style(
      buffer,
      vim.api.nvim_win_get_cursor(0)[1] - 1,
      "Heading " .. level
    )
  end
end

local function toggle_list_line(line_number, list_type)
  local line = vim.fn.getline(line_number)

  if list_type == "bullet" then
    if line:match("^%s*[-*+]%s+") then
      line = line:gsub("^(%s*)[-*+]%s+", "%1")
    else
      line = "- " .. line
    end
  elseif list_type == "number" then
    if line:match("^%s*%d+%.%s+") then
      line = line:gsub("^(%s*)%d+%.%s+", "%1")
    else
      line = "1. " .. line
    end
  end

  vim.fn.setline(line_number, line)
end

function M.attach(buf)
  vim.keymap.set("x", "<leader>b", function()
    wrap_visual("**", "**")
  end, { buffer = buf, desc = "Word Vim: Bold", silent = true })

  vim.keymap.set("x", "<leader>i", function()
    wrap_visual("*", "*")
  end, { buffer = buf, desc = "Word Vim: Italic", silent = true })

  -- Underline uses a compact editor-side marker so it is as easy to
  -- recognize as **bold**, *italic* and ~~strikeout~~.  The DOCX save/open
  -- pipeline converts ++text++ <-> Word custom-style="Underline".
  vim.keymap.set("x", "<leader>u", function()
    wrap_visual("++", "++")
  end, { buffer = buf, desc = "Word Vim: Underline", silent = true })

  vim.keymap.set("x", "<leader>s", function()
    wrap_visual("~~", "~~")
  end, { buffer = buf, desc = "Word Vim: Strikeout", silent = true })

  for level = 1, 6 do
    vim.keymap.set("n", "<leader>" .. level, function()
      set_heading(level)
    end, { buffer = buf, desc = "Word Vim: Heading " .. level })
  end

  vim.keymap.set("n", "<leader>lb", function()
    require("wordvim.lists").toggle_current("bullet")
  end, {
    buffer = buf,
    desc = "Word Vim: Bullet list",
    silent = true,
    nowait = true,
  })

  vim.keymap.set("n", "<leader>ln", function()
    require("wordvim.lists").toggle_current("ordered")
  end, {
    buffer = buf,
    desc = "Word Vim: Numbered list",
    silent = true,
    nowait = true,
  })

  vim.keymap.set("n", "<leader>lx", function()
    require("wordvim.lists").exit_current()
  end, {
    buffer = buf,
    desc = "Word Vim: exit/cancel current list item",
    silent = true,
    nowait = true,
  })


  -- VISUAL MODE: apply/remove list formatting to every selected row.
  vim.keymap.set({ "x", "s" }, "<leader>lb", function()
    require("wordvim.lists").toggle_visual("bullet")
  end, {
    buffer = buf,
    desc = "Word Vim: Bullet list for selection",
    silent = true,
    nowait = true,
  })

  vim.keymap.set({ "x", "s" }, "<leader>ln", function()
    require("wordvim.lists").toggle_visual("ordered")
  end, {
    buffer = buf,
    desc = "Word Vim: Numbered list for selection",
    silent = true,
    nowait = true,
  })
end


function M.setup()
  -- DOCX mappings are attached buffer-locally from wordvim.init.attach().
end

return M
