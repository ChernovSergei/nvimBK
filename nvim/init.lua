--Plugins bootstrap FIRST
require('core.plugins')

--Basics
require('core.configs')
require('core.colors')
require('core.mappings')

--Pluggins
require('plugins.neotree')
require('plugins.treesitter')
--require('plugins.java')
require('plugins.mason')
require('plugins.cmp')
require('plugins.lsp')
--require('plugins.null-ls')
require('plugins.telescope')
require("plugins.conform")
