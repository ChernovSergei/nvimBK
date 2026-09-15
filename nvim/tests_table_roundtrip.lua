-- Run from the project directory:
-- pandoc -f markdown -t plain --lua-filter=tests_table_roundtrip.lua /dev/null
-- Pure table-module/Pandoc tests; Neovim API is stubbed, no Windows UI tested.
local marks, buffers, nextmark = {}, {}, 0
local function copy(x)
 if type(x)~='table' then return x end
 local o={};for k,v in pairs(x)do o[k]=copy(v)end;return o
end
vim={json=pandoc.json, deepcopy=copy,
 trim=function(s)return s:match('^%s*(.-)%s*$')end,api={}}
vim.api.nvim_create_namespace=function()return 1 end
vim.api.nvim_buf_set_extmark=function(b,ns,row,col,opts)
 nextmark=nextmark+1;marks[nextmark]={row,col};return nextmark
end
vim.api.nvim_buf_get_extmark_by_id=function(b,ns,id)return marks[id]or{}end
vim.api.nvim_buf_get_lines=function(b)return buffers[b]end
local source=os.getenv('WORDVIM_TEST_SOURCE')or'lua/wordvim/tables.lua'
local M
if os.getenv('WORDVIM_TEST_BASELINE') then
 local p=assert(io.popen('unzip -p ../WordVim_Neovim_Integrated_v6_50.zip lua/wordvim/tables.lua'))
 local code=p:read('*a');p:close();M=assert(load(code))()
else M=dofile(source) end
local function split(s)
 local o={};for v in (s..'\n'):gmatch('(.-)\n')do o[#o+1]=v end;return o
end
local function has(lines,text)
 for _,v in ipairs(lines)do if v==text then return true end end;return false
end
local s={rows=5,cols=5,header_rows=1,border='grid',cells={}}
for y=1,5 do s.cells[y]={};for x=1,5 do
 s.cells[y][x]={text=y==1 and('Column '..x)or'',style='normal'}
end end
local function meta(s)
 return 'WORDVIM_TABLE_META_'..pandoc.json.encode(s):gsub('.',function(c)return string.format('%02X',c:byte())end)
end
local marker=meta(s)
local out=M.extract({marker,'','## Header','Tail sentinel'})
assert(has(out,'## Header')and has(out,'Tail sentinel'),'missing-table import ate following text')
local adjacent=M.extract({marker,'','## Header','','| A |','| --- |','| B |'})
assert(has(adjacent,'## Header'),'import scanned through unrelated heading')
local input=os.getenv('WORDVIM_TEST_DOCX')
if input then
 local f=assert(io.open(input,'rb'));local bytes=f:read('*a');f:close()
 local md=pandoc.write(pandoc.read(bytes,'docx'),'markdown',{wrap_text='none'})
 local actual, specs=M.extract(split(md))
 assert(has(actual,'## Header'),'uploaded DOCX lost Header')
 assert(#specs==1 and specs[1].rows==5 and specs[1].cols==5,'uploaded table recovery failed')
 io.stderr:write('PASS uploaded DOCX: Header retained, one 5x5 model\n')
end
for cycle=1,3 do
 local shown,specs=M.extract({meta(s)})
 buffers[1]=shown;M.attach_recovered(1,specs)
 local exported,span=M.lines_at(1,0)
 assert(span==7,'incorrect editor span')
 local md=table.concat(exported,'\n')..'\n\n## Header\n\nTail sentinel\n'
 local parsed=pandoc.read(md,'markdown+pipe_tables')
 local count=0;parsed:walk({Table=function()count=count+1 end})
 assert(count==1,'export did not produce exactly one real table')
 local bytes=pandoc.write(parsed,'docx')
 local reopened=pandoc.read(bytes,'docx')
 count=0;reopened:walk({Table=function()count=count+1 end})
 assert(count==1,'DOCX does not contain one real table')
 local readback=pandoc.write(reopened,'markdown-pipe_tables+pipe_tables-grid_tables-simple_tables-multiline_tables',{wrap_text='none'})
 local result,recovered=M.extract(split(readback))
 assert(has(result,'## Header')and has(result,'Tail sentinel'),'roundtrip ate trailing text')
 assert(#recovered==1 and recovered[1].rows==5 and recovered[1].cols==5,'table duplicated or resized')
 s=recovered[1]
 io.stderr:write('PASS DOCX roundtrip '..cycle..': one table, Header and tail retained\n')
end
local html='<table><tr><th colspan="2">Merged</th></tr><tr><td rowspan="2">Vertical</td><td>B</td></tr><tr><td>C</td></tr></table>'
local md=html
local result, specs=M.extract(split(marker..'\n\n'..md..'\n\n## After\nTail sentinel'))
assert(#specs==1 and has(result,'## After')and has(result,'Tail sentinel'),'merged import lost tail')
assert(not table.concat(result,'\n'):find('<table',1,true),'HTML table leaked')
local broken=M.extract({marker,'<table>','<tr>','## After','Tail sentinel'})
assert(has(broken,'## After')and has(broken,'Tail sentinel'),'unclosed HTML ate tail')
io.stderr:write('PASS merged HTML import and incomplete-block tail preservation\n')
