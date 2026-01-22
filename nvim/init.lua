--Basics
require('core.plugins')
require('core.mappings')
require('core.colors')
require('core.configs')

--Pluggins
require('plugins.neotree')
require('plugins.treesitter')
require('plugins.lsp')
require('plugins.mason')
vim.api.nvim_create_autocmd("FileType", {
  pattern = "java",
  callback = function()
    require("plugins.java")
  end,
})
require('plugins.cmp')
