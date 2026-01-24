local lspconfig = require("lspconfig")

-- общие capabilities (cmp, если добавишь позже)
--local capabilities = vim.lsp.protocol.make_client_capabilities()
local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- общий on_attach
local on_attach = function(client, bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }

--  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
end

-- Lua
lspconfig.lua_ls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
  settings = {
    Lua = {
      diagnostics = {
        globals = { "vim" },
      },
    },
  },
})

-- Python
lspconfig.pyright.setup({
  capabilities = capabilities,
  on_attach = on_attach,
})

lspconfig.ts_ls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
})
