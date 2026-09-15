require("mason").setup()
require("mason-lspconfig").setup({
  automatic_enable = { exclude = { "jdtls" } }, -- Java is started by nvim-jdtls.
  ensure_installed = {
    "jdtls",
    "lua_ls",
    "pyright",
    "ts_ls",
    "html",
    "cssls",
    "eslint",
    "emmet_language_server",
  }
})
