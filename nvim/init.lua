-- Keep Neovim ZIP support for normal archives, but do not let
-- the built-in zipPlugin claim .docx files. Word Vim owns *.docx.
vim.g.zipPlugin_ext = table.concat({
  "*.aar", "*.apk", "*.cbz", "*.celzip", "*.crtx",
  "*.docm", "*.dotm", "*.dotx", "*.ear", "*.epub",
  "*.gcsx", "*.glox", "*.gqsx", "*.ja", "*.jar", "*.kmz",
  "*.odb", "*.odc", "*.odf", "*.odg", "*.odi", "*.odm",
  "*.odp", "*.ods", "*.odt", "*.otc", "*.otf", "*.otg",
  "*.oth", "*.oti", "*.otp", "*.ots", "*.ott", "*.oxt",
  "*.pkpass", "*.potm", "*.potx", "*.ppam", "*.ppsm",
  "*.ppsx", "*.pptm", "*.pptx", "*.sldx", "*.thmx",
  "*.vdw", "*.war", "*.whl", "*.wsz", "*.xap", "*.xlam",
  "*.xlsb", "*.xlsm", "*.xlsx", "*.xltm", "*.xltx",
  "*.xpi", "*.zip",
}, ",")

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


-- Word Vim: DOCX editing profile
require("wordvim").setup()
