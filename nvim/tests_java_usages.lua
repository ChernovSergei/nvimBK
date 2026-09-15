vim.opt.rtp:prepend(vim.fn.getcwd())
local config, selected, callback, closed
package.loaded['telescope.pickers']={new=function(_,c) config=c; return {find=function() end} end}
package.loaded['telescope.finders']={new_table=function(o) return o end}
package.loaded['telescope.config']={values={generic_sorter=function() return {} end,qflist_previewer=function() return {} end}}
package.loaded['telescope.actions']={select_default={replace=function(_,f) callback=f end},close=function() closed=true end}
package.loaded['telescope.actions.state']={get_selected_entry=function() return selected end}
vim.lsp.util.locations_to_items=function() return {{filename='C:/some path/Main.java',lnum=3,col=1,text='use()'}} end
local choice={location={},encoding='utf-16'}
local result
require('plugins.java_usages').open({choice},'Java usages',function(c) result=c end)
assert(config.previewer and config.sorter)
selected=config.finder.entry_maker(config.finder.results[1])
config.attach_mappings(1); callback()
assert(closed and result==choice)
require('core.idea_colors').setup()
assert(vim.api.nvim_get_hl(0,{name='@comment.java'}).fg==0x7A7E85)
assert(vim.api.nvim_get_hl(0,{name='@comment.documentation.java'}).fg==0x629755)
print('PASS searchable preview picker selection preserves location; distinct comment colors')
vim.cmd('qa!')
