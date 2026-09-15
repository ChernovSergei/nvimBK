vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile=false
vim.o.columns=160
local root=vim.fn.tempname()
vim.fn.mkdir(root..'/wordvim/panel-colors','p')
local stdpath=vim.fn.stdpath
vim.fn.stdpath=function(k) if k=='state' then return root end;return stdpath(k) end
vim.fn.writefile({'{"Normal":"112233","Heading 1":"445566"}'},root..'/wordvim/panel-colors/old.json')
local colors=require('wordvim.panelcolors')
assert(colors.get(0,'NORMAL')=='112233','legacy overrides not imported')
local styleui=require('wordvim.styleui');styleui.setup()
local styles=require('wordvim.styles')
local function document(path,order)
  vim.cmd('tabnew')
  local b=vim.api.nvim_get_current_buf()
  vim.b[b].wordvim_docx=true;vim.b[b].docx_original_file=path
  local cached={}
  for _,name in ipairs(order) do cached[#cached+1]={name=name,id=name:gsub(' ',''),type='paragraph',color='000000'} end
  styles.set_cached_styles(b,cached)
  vim.api.nvim_buf_set_lines(b,0,-1,false,{'text'})
  styles.set_paragraph_style(b,0,'Normal')
  vim.bo[b].modified=false
  styleui.open(b)
  return b
end
local a=document('one.docx',{'Normal','Heading 1','Zeta'})
local b=document('two.docx',{'Heading 1','Normal','Alpha','Zeta'})
local function bg(buf,index) return vim.api.nvim_get_hl(0,{name='WordVimStyleColor'..buf..'_'..index}).bg end
assert(bg(a,1)==bg(b,1),'same style differs across documents')
local function style_bg(doc,name)
  local sidebar=vim.fn.bufnr('WordVim://Styles/'..doc)
  for i,line in ipairs(vim.api.nvim_buf_get_lines(sidebar,0,-1,false)) do
    if line:match('  '..name..'$') then return bg(doc,i),i end
  end
  error('style missing: '..name)
end
local za,ia=style_bg(a,'Zeta');local zb,ib=style_bg(b,'Zeta')
assert(ia~=ib and za==zb,'default color depends on style number')
assert(colors.set(a,'Normal','AABBCC'))
assert(bg(a,1)==0xAABBCC and bg(b,1)==0xAABBCC,'open panels did not refresh globally')
assert(not vim.bo[a].modified and not vim.bo[b].modified,'palette edit dirtied DOCX')
styleui.close(b)
vim.api.nvim_set_current_buf(b)
require('wordvim.styleeditor').open(b,'Normal')
vim.api.nvim_buf_set_lines(0,14,15,false,{'Panel color HEX      = 123456'})
vim.fn.maparg('<C-s>','n',false,true).callback()
assert(colors.get(a,'Normal')=='123456','editor saved a per-document color')
assert(not vim.bo[b].modified,'color-only editor save dirtied DOCX')
package.loaded['wordvim.panelcolors']=nil
colors=require('wordvim.panelcolors')
assert(colors.get(a,'Normal')=='123456' and colors.get(b,'Normal')=='123456','global persistence')
assert(colors.get(a,'Heading 1')=='445566','migration lost other overrides')
assert(colors.hue('  Normal ')==colors.hue('normal'),'default palette not name-stable')
assert(colors.set(a,'Normal',''))
assert(colors.get(b,'Normal')=='','reset should affect every document')
assert(not colors.set(a,'Normal','123ZZZ'),'invalid color accepted')
print('PASS application palette: migration, different style order, all open documents, persistence, reset, and clean DOCX')
vim.fn.stdpath=stdpath
vim.cmd('qa!')
