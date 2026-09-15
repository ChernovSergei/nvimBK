-- ============================================================
-- lua/wordvim/cursor.lua
-- Global Neovim cursor-shape stabilizer for terminal use.
--
-- v6.23:
-- Some Windows Terminal / Neovim sessions occasionally keep the thin Insert
-- cursor after Neovim has already returned to Normal mode.  The reliable manual
-- recovery found during testing is `:set guicursor=`.  This module automates that
-- exact reset on InsertLeave, and restores the normal Neovim cursor profile on
-- the next InsertEnter.
--
-- This module is deliberately independent from language/layout switching.
-- ============================================================

local M = {}

local ACTIVE_PROFILE = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20"

local function reset_to_terminal_default()
  -- Equivalent to :set guicursor=
  -- This is the operation that reliably restored the block cursor manually.
  vim.o.guicursor = ""
end

local function enable_insert_profile()
  vim.o.guicursor = ACTIVE_PROFILE
end

function M.setup()
  if vim.g.wordvim_cursor_fix == false then
    return
  end

  local group = vim.api.nvim_create_augroup("WordVimCursorShape", { clear = true })

  -- In Normal/Visual/etc. let the terminal use its default cursor.  This is
  -- intentionally the startup state as well.
  reset_to_terminal_default()

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
      enable_insert_profile()
    end,
    desc = "Word Vim cursor: enable thin Insert cursor",
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      -- Run after Neovim has completed the mode transition.  The reset itself
      -- is exactly the same as the successful manual :set guicursor= test.
      vim.schedule(function()
        reset_to_terminal_default()
      end)
    end,
    desc = "Word Vim cursor: reset terminal cursor after Insert",
  })

  -- A few commands leave Insert through intermediate modes.  If Neovim is no
  -- longer in Insert/Replace, make sure a stale Insert beam cannot survive.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*",
    callback = function()
      local mode = vim.api.nvim_get_mode().mode or ""
      local first = mode:sub(1, 1)
      if first ~= "i" and first ~= "R" then
        vim.schedule(function()
          local current = vim.api.nvim_get_mode().mode or ""
          local current_first = current:sub(1, 1)
          if current_first ~= "i" and current_first ~= "R" then
            reset_to_terminal_default()
          end
        end)
      end
    end,
    desc = "Word Vim cursor: keep non-Insert modes on terminal default cursor",
  })

  vim.api.nvim_create_user_command("WordCursorReset", function()
    reset_to_terminal_default()
  end, { desc = "Reset cursor shape to terminal default" })
end

return M
