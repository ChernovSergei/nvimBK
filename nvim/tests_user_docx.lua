vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile=false
if vim.env.WORDVIM_TEST_POWERSHELL then vim.g.wordvim_powershell=vim.env.WORDVIM_TEST_POWERSHELL end
require('wordvim').setup()
local source=vim.fn.getcwd()..'/work/simple-user.docx'
vim.fn.mkdir('work','p')
local input=vim.env.WORDVIM_USER_DOCX
if not input then print('SKIP: set WORDVIM_USER_DOCX to the Apache POI sample');vim.cmd('qa!');return end
assert(vim.uv.fs_copyfile(input,source))
local start=vim.uv.hrtime()
vim.cmd.edit(source)
assert(vim.b.wordvim_docx,'open failed')
assert(table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n'):find('Machinery management',1,true))
print('OPEN SECONDS '..(vim.uv.hrtime()-start)/1e9)
vim.cmd.write()
vim.cmd('bdelete!')
vim.cmd.edit(source)
assert(vim.b.wordvim_docx,'reopen failed')
print('PASS user Apache POI DOCX open/save/reopen')
vim.cmd('qa!')
