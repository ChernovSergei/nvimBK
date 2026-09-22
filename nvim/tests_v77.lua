vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile=false
vim.b.wordvim_docx=true
local captured
package.loaded['wordvim.tables']={insert_fragment=function(lines) captured=table.concat(lines,'\n') end}
local path=vim.fn.tempname()..'.html'
vim.fn.writefile({[[<div style="margin:0"><h1 id="office" style="color:blue"><span style="font-family:Calibri">Заголовок “тест”</span></h1><p><span style="color:red">Текст — €</span> <a href="https://example.com">Link</a></p><table><tr><th><span style="color:blue"><strong>Test 1</strong></span></th><th>B</th></tr><tr><td colspan="2"><span style="font-family:Calibri">Ячейка “два”</span></td></tr></table></div>]]},path)
require('wordvim.clipboard').file(path)
vim.fn.delete(path)
assert(captured:find('Заголовок “тест”',1,true),captured)
assert(captured:find('Текст — €',1,true),captured)
assert(captured:find('https://example.com',1,true),captured)
assert(not captured:find('style=',1,true),captured)
assert(not captured:find('{#office',1,true),captured)
local hex=assert(captured:match('WORDVIM_TABLE_META_(%x+)'),captured)
local model=vim.json.decode((hex:gsub('%x%x',function(x)return string.char(tonumber(x,16))end)))
assert(model.cells[1][1].text=='Test 1',vim.inspect(model))
assert(model.cells[2][1].colspan==2)
assert(model.cells[2][1].text=='Ячейка “два”',vim.inspect(model))
print('PASS office HTML: clean headings/cells, Unicode, bold, links, spans')
vim.cmd('qa!')
