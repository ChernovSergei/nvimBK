vim.o.number = true
vim.o.cursorline = true
vim.o.wrap = false
vim.o.incsearch = true
vim.o.tabstop = 4
vim.o.shiftwidth = 4

vim.g.mapleader = " "

--Portable keyboard shortcuts
vim.keymap.set({"i", "v"}, "<C-a>", "<ESC>")
vim.keymap.set("i", "<C-s>", "<ESC> :w!<CR>")
vim.keymap.set({"i"}, "<A-p>", "+")
vim.keymap.set({"i"}, "<A-CR>", "=")
vim.keymap.set({"i"}, "<A-;>", "\"")
vim.keymap.set({"i"}, "<A-l>", "'")
vim.keymap.set({"i"}, "<A-[>", "\\")

--New window ans switching between the windows
vim.keymap.set( "n", "<C-n>", ":botright vnew<CR>")
vim.keymap.set( "n", "<Tab>", ":wincmd w<CR>")
vim.keymap.set( "n", "<S-Tab>", ":wincmd w<CR>")

--Neotree open main and git view
vim.keymap.set("n", "<leader>e", ":Neotree float focus<CR>")
vim.keymap.set("n", "<leader>o", ":Neotree float git_status<CR>")

--vim.keymap.set({"n", "v"}, "<leader>y", "\"+y")
--vim.keymap.set({"n", "v"}, "<leader>p", "\"+p")


