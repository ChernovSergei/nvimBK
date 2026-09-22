vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile=false
vim.b.wordvim_docx=true
local captured
package.loaded['wordvim.tables']={insert_fragment=function(lines) captured=lines end}
local path=vim.fn.tempname()..'.html'
vim.fn.writefile({[[<html><head><meta charset="utf-8"></head><body><h1>PowerShell</h1><p>Текст “кавычки”</p><p>&nbsp;</p><h2>Notes</h2><ol><li><p>Первый</p></li><li><p>Второй</p></li><li><p>Третий</p></li></ol><table><tr><th><b>Test 1</b></th></tr><tr><td>some infor&nbsp;</td></tr></table><h1>After</h1></body></html>]]},path)
require('wordvim.clipboard').file(path)
vim.fn.delete(path)
assert(captured[1]=='# PowerShell',vim.inspect(captured))
assert(captured[2]=='Текст “кавычки”',vim.inspect(captured))
assert(captured[3]=='',vim.inspect(captured))
assert(captured[4]=='## Notes',vim.inspect(captured))
assert(captured[5]:match('^1%s+Первый$'),vim.inspect(captured))
assert(captured[6]:match('^2%s+Второй$'),vim.inspect(captured))
assert(captured[7]:match('^3%s+Третий$'),vim.inspect(captured))
local hex=assert(captured[8]:match('WORDVIM_TABLE_META_(%x+)'),vim.inspect(captured))
local m=vim.json.decode((hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end)))
assert(m.cells[2][1].text=='some infor',vim.inspect(m))
assert(m.cells[1][1].text=='Test 1' and m.header_rows==1)
assert(captured[9]=='# After',vim.inspect(captured))
print('PASS compact paragraphs, intentional blank, ordered list, NBSP, literal cells, Unicode')
vim.cmd('qa!')
