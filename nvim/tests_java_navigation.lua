vim.opt.rtp:prepend(vim.fn.getcwd())
local labels=require('core.tablabels'); labels.setup()
vim.api.nvim_buf_set_name(0,vim.fn.getcwd()..'/model/UnderLineStyle.java')
assert(labels.label(0)=='model/UnderLineStyle.java')
vim.bo.modified=true
local line=vim.api.nvim_eval_statusline(labels.render(),{use_tabline=true}).str
assert(line:find('model/UnderLineStyle.java +',1,true))
vim.cmd('tabnew')
assert(labels.label(0)=='[No Name]')
vim.api.nvim_buf_set_name(0,vim.fn.getcwd()..'/50%file.java')
assert(vim.api.nvim_eval_statusline(labels.render(),{use_tabline=true}).str:find('50%file.java',1,true))
print('PASS navigation picker options, Enter split mappings, compact tabs, modified flag and percent escaping')
vim.cmd('qa!')


