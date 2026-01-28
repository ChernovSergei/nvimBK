local M = {}

-- ---------- helper ----------
local function java_action_by_title(pattern)
  vim.lsp.buf.code_action({
    apply = true,
    filter = function(action)
      return action.title and action.title:match(pattern)
    end,
  })
end

-- ---------- on_attach ----------
function M.on_attach(_, bufnr)
  local opts = { buffer = bufnr, silent = true, noremap = true }

  -- Show all Java actions
  vim.keymap.set("n", "<leader>j", vim.lsp.buf.code_action, opts)

  -- ===== Code generation =====
  vim.keymap.set("n", "<leader>jc", function()
    java_action_by_title("Constructor")
  end, opts)

  vim.keymap.set("n", "<leader>je", function()
    java_action_by_title("hashCode")
  end, opts)

  vim.keymap.set("n", "<leader>jt", function()
    java_action_by_title("toString")
  end, opts)

  vim.keymap.set("n", "<leader>jm", function()
    java_action_by_title("Override")
  end, opts)

  -- ===== Extract refactors =====
  vim.keymap.set("n", "<leader>em", function()
    java_action_by_title("Extract Method")
  end, opts)

  vim.keymap.set("n", "<leader>ev", function()
    java_action_by_title("Extract Variable")
  end, opts)

  vim.keymap.set("n", "<leader>ec", function()
    java_action_by_title("Extract Constant")
  end, opts)

  -- ===== Imports =====
  vim.keymap.set("n", "<leader>oi", function()
    java_action_by_title("Organize imports")
  end, opts)

  -- ===== Tests (these ARE real APIs) =====
  local jdtls = require("jdtls")
  vim.keymap.set("n", "<leader>tt", jdtls.test_class, opts)
  vim.keymap.set("n", "<leader>tn", jdtls.test_nearest_method, opts)
end

return M
