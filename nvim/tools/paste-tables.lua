-- Convert imported tables into WordVim's portable table model before writing
-- Markdown. This preserves spans that a pipe table alone cannot represent.
local function hex(text)
 return (text:gsub('.',function(c)return string.format('%02X',c:byte())end))
end
-- Keep the filter usable with distribution Pandoc builds without pandoc.json.
local function json(value)
 if type(value)=='string' then
  return '"'..value:gsub('[%z\1-\31\\"]',function(c)
   if c=='"' or c=='\\' then return '\\'..c end
   return string.format('\\u%04x',c:byte())
  end)..'"'
 elseif type(value)=='number' then return tostring(value)
 end
 local parts={}
 if #value>0 then
  for _,v in ipairs(value) do parts[#parts+1]=json(v) end
  return '['..table.concat(parts,',')..']'
 end
 for k,v in pairs(value) do parts[#parts+1]=json(k)..':'..json(v) end
 return '{'..table.concat(parts,',')..'}'
end
function Table(t)
 local rows={}
 local function append(part) for _,r in ipairs(part or {}) do rows[#rows+1]=r end end
 append(t.head.rows)
 local headers=#rows
 for _,body in ipairs(t.bodies) do append(body.head);append(body.body) end
 append(t.foot.rows)
 local cols=#t.colspecs
 if #rows==0 or cols==0 then return end
 if #rows>50 or cols>20 then error('WordVim table import supports up to 50 rows and 20 columns') end
 local model={version=1,rows=#rows,cols=cols,header_rows=headers,border='grid',cells={}}
 local occupied={}
 for y=1,#rows do
  model.cells[y]={};occupied[y]={}
  for x=1,cols do model.cells[y][x]={text='',style='normal',rowspan=1,colspan=1,border='inherit'} end
 end
 for y,row in ipairs(rows) do
  local x=1
  for _,cell in ipairs(row.cells) do
   while occupied[y][x] do x=x+1 end
   if x>cols then error('Invalid imported table column spans') end
   for _,block in ipairs(cell.contents) do
    if block.t=='RawBlock' and block.text:match('^WORDVIM_TABLE_META_') then
     error('Nested tables cannot be imported into the flat WordVim table editor')
    end
   end
   local rs,cs=cell.row_span,cell.col_span
   -- Cells store literal text, not Markdown. Formatting is represented by
   -- the cell style; serializing **bold** here makes the stars actual text.
   local text=pandoc.utils.stringify(cell.contents):gsub('\194\160',' '):gsub('%s+$','')
   local bold=false
   pandoc.Pandoc(cell.contents):walk({Strong=function() bold=true end})
   model.cells[y][x]={text=text,style=y<=headers and 'header' or (bold and 'bold' or 'normal'),rowspan=rs,colspan=cs,border='inherit'}
   for yy=y,math.min(#rows,y+rs-1) do for xx=x,math.min(cols,x+cs-1) do occupied[yy][xx]=true end end
   x=x+cs
  end
 end
 return pandoc.RawBlock('markdown','WORDVIM_TABLE_META_'..hex(json(model)))
end

-- Clean office HTML before serializing cells: otherwise Pandoc exposes CSS
-- as bracketed-span attributes in both the document and table metadata.
return {
 {
  Span=function(el) return el.content end,
  Div=function(el) return el.content end,
  Header=function(el) el.attr=pandoc.Attr();return el end,
 },
 {Table=Table},
 {Pandoc=function(doc)
  -- The editor uses one line per paragraph. Markdown's block separator
  -- blank lines must not become empty Word paragraphs on insertion.
  local out={}
  for _,block in ipairs(doc.blocks) do
   if block.t=='Para' and pandoc.utils.stringify(block):gsub('\194\160',' '):match('^%s*$') then
    out[#out+1]=''
   else
    if block.t=='OrderedList' or block.t=='BulletList' then
     block=block:walk({Para=function(p) return pandoc.Plain(p.content) end})
    end
    local text=pandoc.write(pandoc.Pandoc({block}),'markdown+pipe_tables-smart', {wrap_text='none'}):gsub('\n+$','')
    out[#out+1]=text
   end
  end
  return pandoc.Pandoc({pandoc.RawBlock('markdown',table.concat(out,'\n'))})
 end},
}
