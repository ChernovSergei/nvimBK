vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile=false
vim.g.wordvim_switch_windows_layout=false
require('wordvim').setup()
local path=vim.fn.getcwd()..'/work/title-user.docx'
for i=1,2 do
 vim.cmd.edit(path)
 local lines=vim.api.nvim_buf_get_lines(0,0,-1,false)
 assert(lines[1]=='Global ShortCuts',vim.inspect({lines[1],lines[2],lines[3]}))
 assert(require('wordvim.styles').get_paragraph_style(vim.api.nvim_get_current_buf(),0)=='Title','Title style lost')
 assert(table.concat(lines,'\n'):find('# PowerShell',1,true),'heading lost')
 vim.cmd.write()
 vim.cmd('bdelete!')
end
print('PASS user DOCX Title text/style survives two save/reopen cycles')
vim.cmd('qa!')
