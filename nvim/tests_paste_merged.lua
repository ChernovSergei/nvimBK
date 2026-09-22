vim.opt.rtp:prepend(vim.fn.getcwd());vim.o.swapfile=false
vim.b.wordvim_docx=true
local c=require('wordvim.clipboard');local t=require('wordvim.tables')
vim.fn.mkdir('work','p')
vim.fn.writefile({'<table><tr><th colspan="2">Top</th><th>Other</th></tr><tr><td rowspan="2">Tall</td><td>B</td><td>C</td></tr><tr><td>D</td><td>E</td></tr></table>'},'work/merged-external.html')
c.file('work/merged-external.html')
local model
for row=0,vim.api.nvim_buf_line_count(0)-1 do
 local lines=t.lines_at(vim.api.nvim_get_current_buf(),row)
 if lines then model=vim.json.decode((lines[1]:match('META_(%x+)'):gsub('%x%x',function(x)return string.char(tonumber(x,16))end))) end
end
assert(model and model.rows==3 and model.cols==3)
assert(model.cells[1][1].colspan==2 and model.cells[2][1].rowspan==2)
assert(model.cells[3][2].text=='D' and model.cells[3][3].text=='E')
local rt=require('wordvim.runtime');local old=rt.run_powershell;local old_windows=rt.windows;rt.windows=function()return true end
rt.run_powershell=function(script,sta)
 assert(sta and script:find('ContainsData',1,true))
 return true,vim.fn.getcwd()..'/work/merged-clipboard.html'
end
vim.fn.writefile({'<p>Clipboard text</p><table><tr><td>A</td></tr></table>'},'work/merged-clipboard.html')
c.paste();rt.run_powershell=old;rt.windows=old_windows
assert(table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n'):find('Clipboard text',1,true))
print('PASS external merged-cell coordinates and simulated Windows rich clipboard import')
vim.cmd('qa!')
