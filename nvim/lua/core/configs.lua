vim.wo.number = true
vim.wo.relativenumber = true
vim.o.cursorline = true
vim.o.wrap = false
vim.o.incsearch = true

--vim.g.did_load_filetypes = 1
vim.opt.formatoptions = "qrn1"
vim.opt.showmode = false
vim.opt.updatetime = 100
vim.wo.signcolumn = "yes"
vim.opt.scrolloff = 8
vim.wo.linebreak = true
vim.opt.virtualedit = "block"
vim.opt.undofile = true
vim.opt.shell = vim.fn.executable("zsh") == 1 and "/bin/zsh" or "/bin/bash"

--Mouse
vim.opt.mouse = "a"
vim.opt.mousefocus = true

--Line Numbers
vim.opt.number = true
vim.opt.relativenumber = true

--Splits
vim.opt.splitbelow = true
vim.opt.splitright = true

--Clipboard
vim.opt.clipboard = "unnamedplus"

--Shorter messages
vim.opt.shortmess:append("c")

--Indent Settings
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.smartindent = true

--Fillchars
--vim.opt.fillchars = {
--	vert = "|",
--	fold = " ",
--	eog = " ",
--	msgsep = "-",
--	foldopen = ",",
--	foldsep = "|",
--	foldclose = ">"
--}
