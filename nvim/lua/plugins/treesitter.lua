require('nvim-treesitter.configs').setup {
  ensure_installed = {
      "lua",
      "java",
      "html",
      "css",
      "javascript",
      "typescript",
      "tsx",
      "json",
      "bash",
      "yaml",
      "markdown"
  },

  sync_install = false,
  auto_install = true,
  highlight = {
    enable = true,
    disable = {"html", "css", "javascript", "tsx"}
  },
}
--require'nvim-treesitter'.setup {
  -- Directory to install parsers and queries to (prepended to `runtimepath` to have priority)
--  install_dir = vim.fn.stdpath('data') .. '/site'
--}
--require('nvim-treesitter').install({ 'rust', 'javascript', 'zig' }):wait(300000) -- wait max. 5 minutes
