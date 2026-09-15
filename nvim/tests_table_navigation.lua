-- Pandoc Lua harness: verifies actual editor callbacks with Neovim API stubs.
dofile('tests_table_roundtrip.lua')
local maps,bufs,cursor,config={}, {[1]={}}, {1,0}, nil
vim.o={columns=160,lines=50,cmdheight=1}
local function opts()return setmetatable({},{__index=function(t,k)local v={};rawset(t,k,v);return v end})end
vim.bo=opts();vim.wo=opts()
vim.fn={strdisplaywidth=function(s)return utf8.len(s)end,strcharpart=function(s,a,n)local start=utf8.offset(s,a+1);local last=utf8.offset(s,a+n+1);return s:sub(start,last and last-1 or -1)end}
vim.keymap={set=function(mode,key,fn)maps[key]=fn end}
vim.api.nvim_get_current_buf=function()return 1 end
vim.api.nvim_get_current_win=function()return 1 end
vim.api.nvim_win_get_cursor=function()return cursor end
vim.api.nvim_create_buf=function()bufs[2]={};return 2 end
vim.api.nvim_open_win=function(b,enter,c)config=c;return 2 end
vim.api.nvim_win_set_config=function(w,c)config=c end
vim.api.nvim_win_is_valid=function()return true end
vim.api.nvim_create_autocmd=function()end
vim.api.nvim_buf_set_lines=function(b,a,z,strict,lines)bufs[b]=lines end
vim.api.nvim_buf_get_lines=function(b)return bufs[b]end
vim.api.nvim_win_set_cursor=function(w,c)cursor=c end
vim.api.nvim_win_get_width=function()return config.width end
local prompt
vim.ui={input=function(o,cb)prompt=o.prompt end}
local M=dofile('lua/wordvim/tables.lua')
M.open(5,5)
assert(config.width==158 and config.height==47,'not full workspace')
assert(vim.wo[2].wrap==false,'grid must not wrap')
local function check(y,x)
 local first
 for i,line in ipairs(bufs[2])do if line:sub(1,#'│')=='│' then first=i;break end end
 assert(cursor[1]==first+(y-1)*2,'cursor on border row')
 local line=bufs[2][cursor[1]]
 local ch=line:sub(cursor[2]+1,cursor[2]+1)
 assert(ch~=' ' and ch~='' and ch:byte()~=226,'cursor on border or padding')
 maps['<CR>']();assert(prompt==string.format('Cell %d,%d: ',y,x),'wrong selected cell')
end
check(1,1)
for x=2,5 do maps.l();check(1,x)end
for y=2,5 do maps.j();check(y,5)end
maps.j();check(5,5);maps.w();check(5,5)
maps.b();check(5,4);maps['<Tab>']();check(5,5)
for x=4,1,-1 do maps.h();check(5,x)end
maps.b();check(4,5);maps.w();check(5,1)
for y=4,1,-1 do maps.k();check(y,1)end
maps.b();check(1,1)
io.stderr:write('PASS fullscreen geometry; hjkl, w/b, Tab, boundaries and Enter selection\n')

for _,width in ipairs({160,80,48}) do
 vim.o.columns=width;cursor={1,0};M.open(5,5)
 local header={}
 for _,line in ipairs(bufs[2])do
  if line:sub(1,#'─')=='─' then break end
  assert(#line<=width-2,'help clipped');header[#header+1]=line
 end
 local text=table.concat(header,' ')
 for _,label in ipairs({'Help','Apply','Cancel'})do
  assert(text:find(label,1,true),'missing help: '..label)
 end
 check(1,1);maps.j();check(2,1)
end
io.stderr:write('PASS complete help at 160/80/48 columns and cursor alignment\n')

assert(type(maps['?'])=='function' and maps['?']==maps['<F1>'],'help bindings missing')
local calls=0
package.loaded['wordvim.help']={open=function() calls=calls+1 end}
maps['?']();maps['<F1>']()
assert(calls==2,'table help must delegate to global help')
io.stderr:write('PASS table help delegates to shared help module\n')
