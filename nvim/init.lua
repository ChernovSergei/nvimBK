vim.g.mapleader = " "
vim.g.maplocalleader = " "

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

-- Word Vim startup guard -----------------------------------------------------
-- Some Windows launch paths can append a bare drive root (for example C:\)
-- as a second Neovim argument when a DOCX is opened.  That leaves the drive
-- root in the argument list and later makes :q fail with E173 ("1 more file
-- to edit").  Do not touch normal multi-file invocations; only remove bare
-- drive-root arguments when at least one DOCX argument is present.
local function wordvim_cleanup_accidental_drive_root_arg()
  local argv = vim.fn.argv()
  if type(argv) ~= "table" or #argv < 2 then
    return
  end

  local has_docx = false
  for _, arg in ipairs(argv) do
    if type(arg) == "string" and arg:lower():match("%.docx$") then
      has_docx = true
      break
    end
  end
  if not has_docx then
    return
  end

  local to_delete = {}
  for _, arg in ipairs(argv) do
    if type(arg) == "string" then
      -- C:\, C:/, D:\, ... but NOT ordinary directories such as C:\Docs.
      if arg:match("^[A-Za-z]:[\\/]?$") then
        table.insert(to_delete, arg)
      end
    end
  end

  for _, arg in ipairs(to_delete) do
    pcall(vim.cmd, "argdelete " .. vim.fn.fnameescape(arg))
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = wordvim_cleanup_accidental_drive_root_arg,
  desc = "Word Vim: remove accidental Windows drive-root argv entry",
})

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
