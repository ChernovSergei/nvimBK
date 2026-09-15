vim.opt.rtp:prepend(vim.fn.getcwd())
vim.g.mapleader=' '
vim.o.swapfile=false
local function check(v,msg) assert(v,msg) end
local function keys(s) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(s,true,false,true),'xt',false) end
local function text() return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n') end
local function map(mode,key)
  local m=vim.fn.maparg(key,mode,false,true); assert(type(m.callback)=='function',key); return m.callback
end
local help=require('wordvim.help');help.setup()
for _,ft in ipairs({'java','javascript','wordvim-table',''}) do
  vim.cmd('enew!');vim.bo.filetype=ft
  local b,w=vim.api.nvim_get_current_buf(),vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(b,0,-1,false,{'unsaved'})
  map('n','<F1>')()
  local expected=({java='JAVA',javascript='NODE.JS',['wordvim-table']='DOCX TABLE',['']='FILES'})[ft]
  check(text():find('1. PROJECT: '..expected,1,true),'context '..ft)
  for _,title in ipairs({'2. NEOVIM','3. LINUX','4. POWERSHELL'}) do check(text():find(title,1,true),title) end
  local cfg=vim.api.nvim_win_get_config(0)
  check(cfg.width==vim.o.columns and cfg.height==vim.o.lines-vim.o.cmdheight,'fullscreen')
  check(text():find('CONTENTS',1,true),'contents title')
  local toc=vim.api.nvim_win_get_cursor(0)[1]
  map('n','<Tab>')();map('n','<CR>')()
  check(vim.api.nvim_win_get_cursor(0)[1]>toc+4,'contents link target')
  map('n','<BS>')();check(vim.api.nvim_win_get_cursor(0)[1]==toc,'return to contents')
  map('n','4')(); check(vim.api.nvim_get_current_line()=='4. POWERSHELL','jump')
  vim.o.columns=65;vim.api.nvim_exec_autocmds('VimResized',{})
  check(vim.api.nvim_win_get_config(0).width==65,'resize')
  map('n','<F1>')()
  check(vim.api.nvim_get_current_win()==w and vim.api.nvim_get_current_buf()==b,'return')
  check(text()=='unsaved' and vim.bo.modified,'unchanged buffer')
end
print('PASS help contexts, four sections, geometry, resizing, return and unsaved text')
vim.cmd('enew!')
local b=vim.api.nvim_get_current_buf()
vim.b[b].docx_original_file=vim.fn.getcwd()..'/work/test.docx';vim.b[b].wordvim_docx=true
help.open()
local contents=vim.api.nvim_buf_get_lines(0,0,-1,false)
local count=0
for row=4,#contents do
  local label=contents[row]
  if label=='' then break end
  vim.api.nvim_win_set_cursor(0,{row,0})
  map('n','<CR>')()
  check(vim.api.nvim_get_current_line()==vim.trim(label),'DOCX contents target: '..label)
  check(vim.api.nvim_win_get_cursor(0)[1]>row,'link did not leave contents')
  map('n','<BS>')()
  count=count+1
end
check(count>10,'missing DOCX subsection links')
map('n','<F1>')()
print('PASS every DOCX subsection link and return to contents')
local styles=require('wordvim.styles')
styles.set_cached_styles(b,{{id='Normal',name='Normal',type='paragraph',color='000000'}})
vim.api.nvim_buf_set_lines(b,0,-1,false,{'AlphaBeta'})
vim.bo.autoindent=true
require('wordvim.paragraphs').attach(b)
vim.api.nvim_win_set_cursor(0,{1,5})
map('i','<S-CR>')()
check(text()=='Alpha  \nBeta','hard break content')
check(styles.get_paragraph_style(b,0)=='Normal','first paragraph style')
check(styles.get_paragraph_style(b,1)==nil,'continuation must not have style')
vim.api.nvim_buf_set_lines(b,0,-1,false,{'Alpha'})
vim.api.nvim_win_set_cursor(0,{1,0})
keys('A<S-CR>Beta<Esc>')
check(text()=='Alpha  \nBeta','real Shift+Enter key dispatch')
vim.api.nvim_buf_set_lines(b,0,-1,false,{'Alpha'})
keys('A<C-g><CR>Beta<Esc>')
check(text()=='Alpha  \nBeta','portable line break')
print('PASS Shift+Enter and Ctrl+g Enter with autoindent; continuation style')
local images=require('wordvim.images');images.setup()
vim.api.nvim_buf_set_lines(b,0,-1,false,{'![Picture](<C:/image.png>){width=8cm}'})
vim.api.nvim_win_set_cursor(0,{1,0})
vim.cmd('WordImageScale 50')
check(text()=='![Picture](<C:/image.png>){width=50%}','50 percent width')
vim.cmd('WordImageResize 50')
check(text():find('width=25%%'),'relative resize')
print('PASS image scale 50 and repeated proportional resize')
local old_std=vim.fn.stdpath
vim.fn.stdpath=function(k) if k=='state' then return vim.fn.getcwd()..'/work/test-state' end; return old_std(k) end
local colors=require('wordvim.panelcolors')
check(colors.set(b,'Normal','#1f4e79'),'save color')
package.loaded['wordvim.panelcolors']=nil;colors=require('wordvim.panelcolors')
check(colors.get(b,'Normal')=='1F4E79','persistent color')
check(not colors.set(b,'Normal','BAD'),'invalid color')
check(colors.get(b,'Normal')=='1F4E79','keep previous color')
require('wordvim.styleui').setup();require('wordvim.styleui').open(b)
local hl=vim.api.nvim_get_hl(0,{name='WordVimStyleColor'..b..'_1'})
check(hl.bg==tonumber('1F4E79',16),'panel highlight')
require('wordvim.styleui').close(b)
vim.api.nvim_set_current_buf(b)
require('wordvim.styleeditor').open(b,'Normal',function() end)
check(text():find('Panel color HEX',1,true),'editor color field')
vim.api.nvim_buf_set_lines(0,14,15,false,{'Panel color HEX      = 548235'})
map('n','<C-s>')()
check(colors.get(b,'Normal')=='548235','editor saves panel color')
check(styles.find_style(b,'Normal').color=='000000','text color independent')
check(colors.set(b,'Normal',''),'reset color')
check(colors.get(b,'Normal')=='','automatic palette')
print('PASS panel color persistence, validation, highlight, editor save and reset')
vim.fn.stdpath=old_std
vim.cmd('qa!')
