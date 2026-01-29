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

--Java Debugger
local dap = require("dap")
vim.keymap.set("n", "<leader>5", dap.continue)
vim.keymap.set("n", "<leader>7", dap.step_over)
vim.keymap.set("n", "<leader>8", dap.step_into)
vim.keymap.set("n", "<leader>9", dap.step_out)
vim.keymap.set("n", "<leader>b", dap.toggle_breakpoint)

--Copy and paste from buffer or clipboard
local opts = { noremap = true, silent = true }
vim.keymap.set({ "n", "v" }, "<C-c>", '"+y', opts)
vim.keymap.set( "n", "<C-v>", '"+p', opts)
vim.keymap.set( "i", "<C-v>", '<C-r>+', opts)
vim.keymap.set( "v", "<C-v>", '+p', opts)
