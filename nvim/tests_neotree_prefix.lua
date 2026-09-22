local channel=vim.fn.jobstart({vim.v.progpath,'--headless','-u','NONE','-i','NONE','--embed'},{rpc=true})
assert(channel>0)
local code=[=[
vim.opt.rtp:prepend(...)
vim.o.swapfile=false;vim.o.timeoutlen=600
_G.opened=0;_G.closed=0
package.loaded['neo-tree']={setup=function(config)
 local maps=config.filesystem.window.mappings
 assert(maps.z.nowait==false)
 for _,key in ipairs({'z','zO','zM'}) do
  local spec=maps[key];local name=type(spec)=='table' and spec[1] or spec
  vim.keymap.set('n',key,function()
   if name=='expand_all_subnodes' then _G.opened=_G.opened+1 else _G.closed=_G.closed+1 end
  end,{buffer=0,nowait=type(spec)=='table' and spec.nowait or key~='z'})
 end
end}
require('plugins.neotree')
vim.api.nvim_buf_set_lines(0,0,-1,false,{'tree'})
vim.bo.modifiable=false
]=]
vim.rpcrequest(channel,'nvim_exec_lua',code,{vim.fn.getcwd()})
vim.rpcrequest(channel,'nvim_input','z');vim.wait(40)
vim.rpcrequest(channel,'nvim_input','O');vim.wait(80)
local state=vim.rpcrequest(channel,'nvim_exec_lua','return {_G.opened,_G.closed,vim.bo.modifiable,vim.v.errmsg}',{})
assert(state[1]==1 and state[2]==0 and state[3]==false and state[4]=='',vim.inspect(state))
vim.rpcrequest(channel,'nvim_input','zM');vim.wait(80)
assert(vim.rpcrequest(channel,'nvim_exec_lua','return _G.closed',{})==1)
vim.fn.jobstop(channel)
print('PASS delayed z then O dispatches expand without modifying read-only buffer; zM collapses')
vim.cmd('qa!')

