vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile=false
vim.g.wordvim_switch_windows_layout=false
vim.g.mapleader=' '
local engine=vim.env.WORDVIM_TEST_POWERSHELL
if engine and engine~='' then vim.g.wordvim_powershell=engine end
vim.fn.mkdir('work','p')
local source=vim.fn.getcwd()..'/work/roundtrip-'..(engine and 'core' or 'windows')..'.docx'
local md=vim.fn.getcwd()..'/work/roundtrip.md'
vim.fn.writefile({'# Заголовок','', 'First line  ','Second line','', 'Отдельный абзац','', '- One','- Two','', '| A | B |','|---|---|','| 1 | 2 |','', '![Picture]('..vim.fs.normalize(vim.fn.getcwd())..'/tests629/img.png){width=50%}'},md)
vim.fn.system({'pandoc',md,'-o',source})
assert(vim.v.shell_error==0,'fixture generation')
require('wordvim').setup()
vim.cmd('edit '..vim.fn.fnameescape(source))
local b=vim.api.nvim_get_current_buf()
assert(vim.b[b].wordvim_docx,'DOCX did not load')
local lines=vim.api.nvim_buf_get_lines(b,0,-1,false)
assert(table.concat(lines,'\n'):find('Заголовок',1,true),'Unicode import')
assert(table.concat(lines,'\n'):find('First line  \nSecond line',1,true),'hard break import')
local image_row
for i,line in ipairs(lines) do if line:find('![',1,true) then image_row=i;break end end
assert(image_row,'image import')
vim.api.nvim_win_set_cursor(0,{image_row,0});vim.cmd('WordImageScale 50')
vim.api.nvim_buf_set_lines(b,-1,-1,false,{'Portable save marker'})
vim.cmd('write')
assert(not vim.bo[b].modified,'DOCX save did not succeed')
vim.cmd('bdelete!')
vim.cmd('edit '..vim.fn.fnameescape(source))
local reopened=table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n')
assert(reopened:find('Portable save marker',1,true),'save marker missing')
assert(reopened:find('width=50%',1,true),'percent metadata lost')
assert(reopened:find('Заголовок',1,true),'Unicode lost')
local ok,xml_error=require('wordvim.runtime').run_powershell(([=[
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::OpenRead('%s')
try {
  $r=New-Object IO.StreamReader($z.GetEntry('word/document.xml').Open())
  try { [xml]$x=$r.ReadToEnd() } finally { $r.Dispose() }
  $n=New-Object Xml.XmlNamespaceManager($x.NameTable)
  $n.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
  if($x.SelectNodes('//w:tbl',$n).Count -ne 1){throw 'Table lost'}
  if($x.SelectNodes('//w:drawing',$n).Count -ne 1){throw 'Image lost'}
  if($x.SelectNodes('//w:numPr',$n).Count -lt 2){throw 'List lost'}
  $p=$x.SelectSingleNode('//w:p[.//w:t[text()="First line"]]',$n)
  if(!$p -or !$p.InnerText.Contains('Second line') -or $p.SelectNodes('.//w:br',$n).Count -ne 1){throw 'Word hard line break became a separate paragraph'}
} finally {$z.Dispose()}
]=]):format(source:gsub("'","''")))
assert(ok,xml_error)
print('PASS OXML table, image, list and hard-break structure')
print('PASS full DOCX import/save/reopen through '..(engine or require('wordvim.runtime').powershell()))
vim.cmd('qa!')
