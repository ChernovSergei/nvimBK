-- ============================================================
-- lua/wordvim/paragraphs.lua
--
-- Word-like paragraph behavior for DOCX buffers:
--
-- Enter       = new Word paragraph
-- Shift+Enter = line break inside the same Word paragraph
--
-- Word Vim keeps the EDITOR view compact: there are no visible
-- empty separator rows between ordinary paragraphs.
--
-- Enter inserts ONE new editor row. During DOCX save, docx.lua
-- reconstructs the blank Markdown separators required by Pandoc.
--
-- Shift+Enter inserts a Markdown hard line break (two trailing
-- spaces + newline), which Pandoc writes to DOCX as a line break
-- inside the same Word paragraph.
-- ============================================================

local M = {}

local indents = require("wordvim.indents")

local attached = {}

local function is_wordvim_docx(buf)
  return vim.b[buf].docx_original_file ~= nil
end

function M.attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if not is_wordvim_docx(buf) then
    return
  end

  if attached[buf] then
    return
  end

  attached[buf] = true

  -- Word behavior:
  -- one Enter creates a NEW paragraph, without leaving a visible
  -- blank line in the editor.
  vim.keymap.set(
    "i",
    "<CR>",
    function()
      local old_row = vim.api.nvim_win_get_cursor(0)[1] - 1

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          local new_row = math.min(
            old_row + 1,
            vim.api.nvim_buf_line_count(buf) - 1
          )
          indents.copy_indent(buf, old_row, new_row)
        end
      end)

      return "<CR>"
    end,
    {
      buffer = buf,
      expr = true,
      noremap = true,
      silent = true,
      desc = "Word Vim: new Word paragraph",
    }
  )

  -- Word Shift+Enter behavior:
  -- line break inside the SAME paragraph.
  vim.keymap.set(
    "i",
    "<S-CR>",
    "  <CR>",
    {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = "Word Vim: line break inside paragraph",
    }
  )
end

function M.detach(buf)
  attached[buf] = nil
end

function M.setup()
  -- Mappings are attached explicitly by docx.lua after a DOCX
  -- has been converted and initialized.
end

return M
