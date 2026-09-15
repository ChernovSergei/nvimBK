-- Word Vim floating table editor. Tables are represented by one line in the
-- document buffer and expanded to HTML only while Pandoc creates the DOCX.
local M = {}
local ns = vim.api.nvim_create_namespace("WordVimTables")
local states, PREFIX, LABEL = {}, "WORDVIM_TABLE_META_", "[WordVim table]"

local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function hex(s) return (s:gsub(".",function(c)return string.format("%02X",c:byte())end)) end
local function unhex(s) if #s%2>0 then return end;return(s:gsub("%x%x",function(x)return string.char(tonumber(x,16))end))end
local function encode(x)return PREFIX..hex(vim.json.encode(x))end
local function decode(s)local x=(s or""):match(PREFIX.."([%x]+)");if not x then return end;local ok,v=pcall(vim.json.decode,unhex(x));return ok and v or nil end
local function cell(text,style)return{text=text or"",style=style or"normal",rowspan=1,colspan=1,border="inherit"}end
local function newspec(r,c)
 r,c=clamp(tonumber(r)or 3,1,50),clamp(tonumber(c)or 3,1,20)
 local s={version=1,rows=r,cols=c,header_rows=1,border="grid",cells={}}
 for y=1,r do s.cells[y]={};for x=1,c do s.cells[y][x]=cell(y==1 and("Column "..x)or"",y==1 and"header"or"normal")end end
 return s
end
local styles={normal=true,header=true,bold=true,italic=true,accent=true,warning=true,note=true}
local function normalize(s)
 s.rows,s.cols=clamp(tonumber(s.rows)or 1,1,50),clamp(tonumber(s.cols)or 1,1,20);s.version=1
 s.header_rows=clamp(tonumber(s.header_rows)or 0,0,s.rows);s.border=({grid=true,outer=true,none=true})[s.border]and s.border or"grid";s.cells=s.cells or{}
 for y=1,s.rows do s.cells[y]=s.cells[y]or{};for x=1,s.cols do local q=s.cells[y][x]or cell();q.text=tostring(q.text or"");q.style=styles[q.style]and q.style or"normal";q.border=q.border or"inherit";q.rowspan=clamp(tonumber(q.rowspan)or 1,1,s.rows-y+1);q.colspan=clamp(tonumber(q.colspan)or 1,1,s.cols-x+1);s.cells[y][x]=q end end
 return s
end
local function cover(s)
 local m={};for y=1,s.rows do m[y]={}end
 for y=1,s.rows do for x=1,s.cols do if not m[y][x]then local q=s.cells[y][x];for yy=y,y+q.rowspan-1 do for xx=x,x+q.colspan-1 do m[yy][xx]={y=y,x=x,h=xx>x,v=yy>y}end end end end end
 return m
end
local function owner(s,y,x)local q=cover(s)[y][x];return q.y,q.x end
local function esc(s)return tostring(s):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;"):gsub("\n","<br>")end
local function summary(s)
 local n=0;for y=1,s.rows do for x=1,s.cols do local q=s.cells[y][x];if q.rowspan>1 or q.colspan>1 then n=n+1 end end end
 return string.format("%s %d x %d | header: %d | borders: %s%s",LABEL,s.rows,s.cols,s.header_rows,s.border,n>0 and(" | merged: "..n)or"")
end
local function display(s)
 local out={summary(s)}
 for y=1,s.rows do local p={"|"};for x=1,s.cols do local q=s.cells[y][x];local t=q.text:gsub("\n"," ↵ "):gsub("|","¦");p[#p+1]=" "..t.." |"end;out[#out+1]=table.concat(p);if y==1 then local z={"|"};for _=1,s.cols do z[#z+1]=" --- |"end;out[#out+1]=table.concat(z)end end
 return out
end
local function html(s)
 -- A pipe table must start a separate Markdown block.
 local o={encode(s), ""}
 for y=1,s.rows do local parts={"|"};for x=1,s.cols do local q=s.cells[y][x];local t=q.text:gsub("|","\\|"):gsub("\n","<br>");if q.style=="bold"or q.style=="header"then t="**"..t.."**"elseif q.style=="italic"then t="*"..t.."*"end;parts[#parts+1]=" "..t.." |"end;o[#o+1]=table.concat(parts);if y==1 then local sep={"|"};for _=1,s.cols do sep[#sep+1]=" --- |"end;o[#o+1]=table.concat(sep)end end
 return o
end
local function state(b)states[b]=states[b]or{items={},next=1};return states[b]end
local function bounds(b,it)local p=vim.api.nvim_buf_get_extmark_by_id(b,ns,it.mark,{});local q=vim.api.nvim_buf_get_extmark_by_id(b,ns,it.finish,{});return#p>0 and p[1]or nil,#q>0 and q[1]or nil end
local function rowof(b,it)local p=bounds(b,it);return p end
local function attach(b,row,s)
 local st=state(b);local id=st.next;st.next=id+1;s=normalize(s);local mark=vim.api.nvim_buf_set_extmark(b,ns,row,0,{right_gravity=true});local finish=vim.api.nvim_buf_set_extmark(b,ns,row+#display(s),0,{right_gravity=false});local it={id=id,mark=mark,finish=finish,spec=s};st.items[id]=it;return it
end
local function current(b)
 local r=vim.api.nvim_win_get_cursor(0)[1]-1;local st=state(b)
 for _,it in pairs(st.items)do local a,z=bounds(b,it);if a and z and r>=a and r<z then return it end end
 local lines=vim.api.nvim_buf_get_lines(b,0,-1,false);local first=r
 while first>=0 and not(lines[first+1]or""):find(LABEL,1,true)do if not vim.trim(lines[first+1]or""):match("^|.*|$")then return nil end;first=first-1 end
 if first<0 then return nil end
 for _,it in pairs(st.items)do if summary(it.spec)==lines[first+1]then vim.api.nvim_buf_del_extmark(b,ns,it.mark);vim.api.nvim_buf_del_extmark(b,ns,it.finish);it.mark=vim.api.nvim_buf_set_extmark(b,ns,first,0,{right_gravity=true});it.finish=vim.api.nvim_buf_set_extmark(b,ns,first+#display(it.spec),0,{right_gravity=false});return it end end
end
local function replace_item(b,it,s)
 local a=select(1,bounds(b,it));if not a then return end;local st=state(b);st.updating=true;local old_count=#display(it.spec);it.spec=normalize(vim.deepcopy(s));local lines=display(it.spec)
 -- Remove both anchors before replacing the range. Otherwise Neovim moves
 -- the start anchor to the end of inserted text and the protection callback
 -- repeatedly restores another copy of the same table.
 vim.api.nvim_buf_del_extmark(b,ns,it.mark);vim.api.nvim_buf_del_extmark(b,ns,it.finish)
 vim.api.nvim_buf_set_lines(b,a,a+old_count,false,lines)
 it.mark=vim.api.nvim_buf_set_extmark(b,ns,a,0,{right_gravity=true});it.finish=vim.api.nvim_buf_set_extmark(b,ns,a+#lines,0,{right_gravity=false});st.updating=false
end

function M.expand_lines(b,lines)
 local at={};for _,it in pairs(state(b).items)do local r=rowof(b,it);if r then at[r]=it end end
 local o={};for i,line in ipairs(lines)do if at[i-1]then vim.list_extend(o,html(at[i-1].spec))else o[#o+1]=line end end;return o
end
function M.lines_at(b,row)
 for _,it in pairs(state(b).items)do local a=select(1,bounds(b,it));if a==row then return html(it.spec),#display(it.spec) end end
end
local function pipe_cells(line)
 local s=vim.trim(line or""):gsub("^|",""):gsub("|$","");local out={};local token="__WORDVIM_ESCAPED_PIPE_9C2A__";s=s:gsub("\\|",token)
 for part in(s.."|"):gmatch("(.-)|")do local v=vim.trim(part):gsub(token,"|");out[#out+1]=v end
 return out
end
local function legacy_spec(lines,first,last)
 local header=pipe_cells(lines[first]);local data={header}
 for i=first+2,last do data[#data+1]=pipe_cells(lines[i])end
 local s=newspec(#data,#header);s.header_rows=1
 for y,row in ipairs(data)do for x=1,s.cols do local v=row[x]or"";local style=y==1 and"header"or"normal";if v:match("^%*%*.*%*%*$")then v=v:sub(3,-3);style="bold"elseif v:match("^%*.*%*$")then v=v:sub(2,-2);style="italic"end;s.cells[y][x]=cell(v,style)end end
 return s
end
function M.extract(lines)
 local specs,o,map,i={}, {},{},1
 while i<=#lines do local first=i;local s=decode(lines[i]);if s then
  specs[#specs+1]=normalize(s);i=i+1
  -- Only consume an immediately adjacent pipe table, never search through
  -- following paragraphs. Older exports may have no real table at all.
  local candidate=i
  while candidate<=#lines and vim.trim(lines[candidate])=="" do candidate=candidate+1 end
  -- Pandoc uses HTML for row/column spans. Consume only a complete adjacent
  -- table; never scan past a following Markdown heading or another marker.
  if candidate<=#lines and vim.trim(lines[candidate]):match("^<table[%s>]") then
   local depth,last=0,nil
   for row=candidate,#lines do
    local line=lines[row]
    if line:match("^%s*#") or decode(line) then break end
    for closing in line:gmatch("<(/?)table[%s>]") do
     depth=depth+(closing=="/" and -1 or 1)
     if depth==0 then last=row;break end
    end
    if last then break end
   end
   if last then i=last+1 end
  end
  if candidate<#lines and vim.trim(lines[candidate]):match("^|.*|$")
    and vim.trim(lines[candidate+1]):match("^|[%s:|%-]+|$") then
   i=candidate+2
   local remaining=specs[#specs].rows-1
   while remaining>0 and i<=#lines and vim.trim(lines[i]):match("^|.*|$") do
    i=i+1;remaining=remaining-1
   end
  end
  local shown=display(specs[#specs]);for _,v in ipairs(shown)do o[#o+1]=v end;map[first-1]=#o-#shown
  elseif vim.trim(lines[i]):match("^|.*|$")and i<#lines and vim.trim(lines[i+1]):match("^|[%s:|%-]+|$")then local last=i+1;while last+1<=#lines and vim.trim(lines[last+1]):match("^|.*|$")do last=last+1 end;local migrated=legacy_spec(lines,i,last);specs[#specs+1]=migrated;local shown=display(migrated);for _,v in ipairs(shown)do o[#o+1]=v end;map[i-1]=#o-#shown;i=last+1
  else o[#o+1]=lines[i];map[i-1]=#o-1;i=i+1 end end
 return o,specs,map
end
function M.attach_recovered(b,specs)
 states[b]={items={},next=1};local n=1;for i,line in ipairs(vim.api.nvim_buf_get_lines(b,0,-1,false))do if line:find(LABEL,1,true)and specs[n]then attach(b,i-1,specs[n]);n=n+1 end end
end
local absorb_text
function M.validate(b)
 local lines=vim.api.nvim_buf_get_lines(b,0,-1,false)
 for _,it in pairs(state(b).items)do local a=select(1,bounds(b,it));if not a then return false,"table anchor is missing"end;local count=#display(it.spec);local block={};for i=a+1,a+count do block[#block+1]=lines[i]or""end;local copy=vim.deepcopy(it.spec);if not absorb_text(copy,block)then return false,string.format("invalid table structure near editor line %d",a+1)end end
 return true
end
absorb_text=function(s,lines)
 local canonical=display(s);if#lines~=#canonical or lines[1]~=canonical[1]or lines[3]~=canonical[3]then return false end
 local changed=false
 for y=1,s.rows do local idx=y==1 and 2 or y+2;local values=pipe_cells(lines[idx]);if#values~=s.cols then return false end;for x=1,s.cols do local v=values[x]:gsub("¦","|"):gsub(" ↵ ","\n");if s.cells[y][x].text~=v then s.cells[y][x].text=v;changed=true end end end
 return true,changed
end
function M.protect(b)
 local g=vim.api.nvim_create_augroup("WordVimTableProtect"..b,{clear=true})
 local function check()vim.schedule(function()if not vim.api.nvim_buf_is_valid(b)then return end;local st=state(b);if st.updating then return end;for _,it in pairs(st.items)do local a,z=bounds(b,it);if a and z then local want=display(it.spec);local got=vim.api.nvim_buf_get_lines(b,a,z,false);if not vim.deep_equal(got,want)then local valid=absorb_text(it.spec,got);if not valid then replace_item(b,it,it.spec);vim.bo[b].modified=true;vim.notify("Word Vim: table structure can only be changed with :WordTable",vim.log.levels.WARN)end end end end end)end
 vim.api.nvim_create_autocmd({"TextChanged","TextChangedI"},{group=g,buffer=b,callback=check})
end

local function draw(s)
 local m,o=cover(s.spec),{}
 local width=math.max(1,vim.api.nvim_win_get_width(s.win))
 local function help(text)
  local line=""
  for word in text:gmatch("%S+") do
   if #line>0 and #line+1+#word>width then o[#o+1]=line;line="" end
   while #word>width do
    if #line>0 then o[#o+1]=line;line="" end
    o[#o+1]=word:sub(1,width);word=word:sub(width+1)
   end
   if #word>0 then line=line=="" and word or line.." "..word end
  end
  if #line>0 then o[#o+1]=line end
 end
 help(string.format("TABLE EDITOR %dx%d | Header:%d | Lines:%s",s.spec.rows,s.spec.cols,s.spec.header_rows,s.spec.border))
 help("?: Help | F1: Help | W: Apply | q: Cancel")
 o[#o+1]=string.rep("─",math.min(width,15*s.spec.cols+1))
 local first_cell_row=#o+1
 s.pos={}

 for y=1,s.spec.rows do local parts,col={},0;s.pos[y]={};for x=1,s.spec.cols do local z=m[y][x];if z.y==y and z.x==x then local q=s.spec.cells[y][x];local t=q.text:gsub("\n"," ");if vim.fn.strdisplaywidth(t)>8 then t=vim.fn.strcharpart(t,0,7).."…"end;if t==""then t="·"end;if q.style~="normal"then t=t.."{"..q.style:sub(1,1):upper().."}"end;if q.rowspan>1 or q.colspan>1 then t=t..string.format("[%dx%d]",q.rowspan,q.colspan)end;t=t..string.rep(" ",math.max(0,11-vim.fn.strdisplaywidth(t)));parts[#parts+1]="│ "..t.." ";s.pos[y][x]=col+#"│ ";col=col+#parts[#parts] elseif z.h then parts[#parts+1]="             ";col=col+#parts[#parts] else parts[#parts+1]="│     ↥      ";s.pos[y][x]=col+#"│ ";col=col+#parts[#parts] end end;o[#o+1]=table.concat(parts).."│";o[#o+1]=string.rep("─",math.min(178,14*s.spec.cols+1))end
 vim.bo[s.buf].modifiable=true;vim.api.nvim_buf_set_lines(s.buf,0,-1,false,o);vim.bo[s.buf].modifiable=false;local y,x=owner(s.spec,s.y,s.x);s.y,s.x=y,x;vim.api.nvim_win_set_cursor(s.win,{first_cell_row+(y-1)*2,s.pos[y][x]or 0})
end
local function select(items,prompt,cb)vim.ui.select(items,{prompt=prompt},function(v)if v then cb(v)end end)end
local function finish(s,save)
 if save then if s.item then replace_item(s.source,s.item,s.spec)else local r=vim.api.nvim_win_get_cursor(s.source_win)[1];local lines=display(s.spec);local st=state(s.source);st.updating=true;vim.api.nvim_buf_set_lines(s.source,r,r,false,lines);local it=attach(s.source,r,s.spec);st.updating=false end;vim.bo[s.source].modified=true end
 if vim.api.nvim_win_is_valid(s.win)then vim.api.nvim_win_close(s.win,true)end
end
local function show_help()
 local lines={
 "WORD VIM TABLE HELP", "",
 "hjkl / arrows - select a neighbouring cell",
 "w / Tab - next cell; b / Shift-Tab - previous cell",
 "Enter - edit selected cell text",
 "Space - set selection anchor; M - merge selection",
 "U - split selected merged cell",
 "S - cell style; B - cell borders; L - table borders",
 "H - number of header rows",
 "A - add row at end; D - delete selected row",
 "I - insert column after selection; X - delete column",
 "R - delete existing table (confirmation required)",
 "W - apply changes to document buffer and close editor",
 "q / Q - close editor without applying changes",
 "Save the DOCX separately with :w in the document.", "",
 "In document: Space w t - open/create table",
 "Close this help: q, Esc, ?, or F1"}
 local b=vim.api.nvim_create_buf(false,true)
 vim.bo[b].bufhidden="wipe"
 vim.api.nvim_buf_set_lines(b,0,-1,false,lines)
 vim.bo[b].modifiable=false
 local width=math.max(1,math.min(76,vim.o.columns-4))
 local height=math.max(1,math.min(#lines+2,vim.o.lines-vim.o.cmdheight-4))
 local win=vim.api.nvim_open_win(b,true,{relative="editor",row=1,col=math.max(0,math.floor((vim.o.columns-width)/2)),width=width,height=height,style="minimal",border="rounded",title=" Table help ",zindex=60})
 vim.wo[win].wrap=true
 for _,key in ipairs({"q","<Esc>","?","<F1>"})do
  vim.keymap.set("n",key,function()if vim.api.nvim_win_is_valid(win)then vim.api.nvim_win_close(win,true)end end,{buffer=b,silent=true,nowait=true})
 end
end
local function open_editor(it,r,c)
 local source,sw=vim.api.nvim_get_current_buf(),vim.api.nvim_get_current_win();local spec=it and vim.deepcopy(it.spec)or newspec(r,c);local b=vim.api.nvim_create_buf(false,true);vim.bo[b].buftype="nofile";vim.bo[b].bufhidden="wipe";vim.bo[b].filetype="wordvim-table";local function geometry()
 return {relative="editor",row=0,col=0,width=math.max(1,vim.o.columns-2),height=math.max(1,vim.o.lines-vim.o.cmdheight-2),style="minimal",border="rounded",title=" Word Vim Table Editor ",title_pos="center"}
 end
 local win=vim.api.nvim_open_win(b,true,geometry())
 vim.wo[win].wrap=false
;local s={buf=b,win=win,source=source,source_win=sw,item=it,spec=spec,y=1,x=1};local op={buffer=b,silent=true,nowait=true}
 vim.keymap.set("n","?",show_help,op)
 vim.keymap.set("n","<F1>",show_help,op)
 local function move(dy,dx)
  local y,x=s.y,s.x
  while true do
   y,x=y+dy,x+dx
   if y<1 or y>s.spec.rows or x<1 or x>s.spec.cols then break end
   local ay,ax=owner(s.spec,y,x)
   if ay~=s.y or ax~=s.x then s.y,s.x=ay,ax;break end
  end
  draw(s)
 end
 local function step(delta)
  local index=(s.y-1)*s.spec.cols+s.x
  while true do
   index=index+delta
   if index<1 or index>s.spec.rows*s.spec.cols then break end
   local y=math.floor((index-1)/s.spec.cols)+1
   local x=(index-1)%s.spec.cols+1
   local ay,ax=owner(s.spec,y,x)
   if ay==y and ax==x then s.y,s.x=y,x;break end
  end
  draw(s)
 end
 for key,d in pairs({h={0,-1},l={0,1},j={1,0},k={-1,0},["<Left>"]={0,-1},["<Right>"]={0,1},["<Down>"]={1,0},["<Up>"]={-1,0}})do
  vim.keymap.set("n",key,function()move(d[1],d[2])end,op)
 end
 for _,key in ipairs({"w","<Tab>"})do vim.keymap.set("n",key,function()step(1)end,op)end
 for _,key in ipairs({"b","<S-Tab>"})do vim.keymap.set("n",key,function()step(-1)end,op)end
 local resize=vim.api.nvim_create_autocmd("VimResized",{callback=function()
  if vim.api.nvim_win_is_valid(win)then vim.api.nvim_win_set_config(win,geometry());draw(s)end
 end})
 vim.api.nvim_create_autocmd("BufWipeout",{buffer=b,once=true,callback=function()
  pcall(vim.api.nvim_del_autocmd,resize)
 end})
 vim.keymap.set("n","<CR>",function()local y,x=owner(s.spec,s.y,s.x);vim.ui.input({prompt=string.format("Cell %d,%d: ",y,x),default=s.spec.cells[y][x].text},function(v)if v~=nil then s.spec.cells[y][x].text=v;draw(s)end end)end,op)
 vim.keymap.set("n","<Space>",function()s.anchor={s.y,s.x};vim.notify("Word Vim: anchor set; move and press M")end,op)
 vim.keymap.set("n","M",function()if not s.anchor then s.anchor={s.y,s.x};vim.notify("Word Vim: anchor set; move and press M");return end;local y1,y2=math.min(s.anchor[1],s.y),math.max(s.anchor[1],s.y);local x1,x2=math.min(s.anchor[2],s.x),math.max(s.anchor[2],s.x);local texts={};for y=y1,y2 do for x=x1,x2 do local ay,ax=owner(s.spec,y,x);local q=s.spec.cells[ay][ax];if ay<y1 or ax<x1 or ay+q.rowspan-1>y2 or ax+q.colspan-1>x2 then s.anchor=nil;vim.notify("Selection cuts an existing merged cell",vim.log.levels.ERROR);return end;if ay==y and ax==x and q.text~=""then texts[#texts+1]=q.text end;q.rowspan,q.colspan=1,1 end end;local q=s.spec.cells[y1][x1];q.text=table.concat(texts," ");q.rowspan,q.colspan=y2-y1+1,x2-x1+1;s.y,s.x,s.anchor=y1,x1,nil;draw(s)end,op)
 vim.keymap.set("n","U",function()local y,x=owner(s.spec,s.y,s.x);s.spec.cells[y][x].rowspan,s.spec.cells[y][x].colspan=1,1;draw(s)end,op)
 vim.keymap.set("n","S",function()local y,x=owner(s.spec,s.y,s.x);select({"normal","bold","italic","accent","warning","note","header"},"Cell style",function(v)s.spec.cells[y][x].style=v;draw(s)end)end,op)
 vim.keymap.set("n","B",function()local y,x=owner(s.spec,s.y,s.x);select({"inherit","none","thin","thick"},"Cell borders",function(v)s.spec.cells[y][x].border=v;draw(s)end)end,op)
 vim.keymap.set("n","L",function()select({"grid","outer","none"},"Table borders",function(v)s.spec.border=v;draw(s)end)end,op)
 vim.keymap.set("n","H",function()vim.ui.input({prompt="Header rows: ",default=tostring(s.spec.header_rows)},function(v)if tonumber(v)then s.spec.header_rows=clamp(tonumber(v),0,s.spec.rows);draw(s)end end)end,op)
 vim.keymap.set("n","A",function()if s.spec.rows>=50 then return end;s.spec.rows=s.spec.rows+1;s.spec.cells[s.spec.rows]={};for x=1,s.spec.cols do s.spec.cells[s.spec.rows][x]=cell()end;draw(s)end,op)
 vim.keymap.set("n","D",function()if s.spec.rows<=1 then return end;table.remove(s.spec.cells,s.y);s.spec.rows=s.spec.rows-1;s.y=clamp(s.y,1,s.spec.rows);normalize(s.spec);draw(s)end,op)
 vim.keymap.set("n","I",function()if s.spec.cols>=20 then return end;s.spec.cols=s.spec.cols+1;for y=1,s.spec.rows do table.insert(s.spec.cells[y],s.x+1,cell())end;normalize(s.spec);draw(s)end,op)
 vim.keymap.set("n","X",function()if s.spec.cols<=1 then return end;for y=1,s.spec.rows do table.remove(s.spec.cells[y],s.x)end;s.spec.cols=s.spec.cols-1;s.x=clamp(s.x,1,s.spec.cols);normalize(s.spec);draw(s)end,op)
 vim.keymap.set("n","R",function()if not s.item then vim.notify("Word Vim: the new table has not been inserted yet");return end;select({"Cancel","Delete table"},"Delete this table?",function(v)if v=="Delete table"then local a,z=bounds(s.source,s.item);local st=state(s.source);st.items[s.item.id]=nil;st.updating=true;vim.api.nvim_buf_del_extmark(s.source,ns,s.item.mark);vim.api.nvim_buf_del_extmark(s.source,ns,s.item.finish);if a then vim.api.nvim_buf_set_lines(s.source,a,z or a+1,false,{})end;st.updating=false;vim.bo[s.source].modified=true;finish(s,false)end end)end,op)
 vim.keymap.set("n","W",function()finish(s,true)end,op);vim.keymap.set("n","Q",function()finish(s,false)end,op);vim.keymap.set("n","q",function()finish(s,false)end,op);draw(s)
end
function M.open(r,c)local b=vim.api.nvim_get_current_buf();open_editor(current(b),r,c)end

-- Apply table/header/cell border and fill metadata to Pandoc's DOCX.
function M.apply_to_docx(docx)
 if vim.fn.has("win32")~=1 and vim.fn.has("win64")~=1 then return true end
 local path=tostring(docx):gsub("'","''")
 local ps=string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::Open('%s','Update');try{$e=$z.GetEntry('word/document.xml');$r=New-Object IO.StreamReader($e.Open());$t=$r.ReadToEnd();$r.Close();$x=New-Object Xml.XmlDocument;$x.PreserveWhitespace=$true;$x.LoadXml($t);$n=New-Object Xml.XmlNamespaceManager($x.NameTable);$n.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main');$u=$n.LookupNamespace('w')
foreach($p in @($x.SelectNodes('//w:p',$n))){$v=($p.SelectNodes('.//w:t',$n)|%%{$_.InnerText})-join'';if($v-match'WORDVIM_TABLE_META_([0-9A-Fa-f]+)'){$h=$Matches[1];$a=for($i=0;$i-lt$h.Length;$i+=2){[Convert]::ToByte($h.Substring($i,2),16)};$s=([Text.Encoding]::UTF8.GetString($a)|ConvertFrom-Json);$tb=$p.NextSibling;while($tb-and$tb.LocalName-ne'tbl'){$tb=$tb.NextSibling};if(!$tb){continue};$tp=$tb.SelectSingleNode('./w:tblPr',$n);if(!$tp){$tp=$x.CreateElement('w','tblPr',$u);[void]$tb.PrependChild($tp)};$old=$tp.SelectSingleNode('./w:tblBorders',$n);if($old){[void]$tp.RemoveChild($old)};if($s.border-ne'none'){$bd=$x.CreateElement('w','tblBorders',$u);$names=@('top','left','bottom','right');if($s.border-eq'grid'){$names+=@('insideH','insideV')};foreach($nn in $names){$q=$x.CreateElement('w',$nn,$u);$q.SetAttribute('val',$u,'single');$q.SetAttribute('sz',$u,'8');$q.SetAttribute('color',$u,'808080');[void]$bd.AppendChild($q)};[void]$tp.AppendChild($bd)};$rows=@($tb.SelectNodes('./w:tr',$n));$orig=New-Object Collections.ArrayList;foreach($rr in $rows){[void]$orig.Add(@($rr.SelectNodes('./w:tc',$n)))};for($y=0;$y-lt$rows.Count;$y++){if($y-lt[int]$s.header_rows){$rp=$rows[$y].SelectSingleNode('./w:trPr',$n);if(!$rp){$rp=$x.CreateElement('w','trPr',$u);[void]$rows[$y].PrependChild($rp)};$hh=$x.CreateElement('w','tblHeader',$u);$hh.SetAttribute('val',$u,'true');[void]$rp.AppendChild($hh)};$cs=@($rows[$y].SelectNodes('./w:tc',$n));for($ci=0;$ci-lt$cs.Count;$ci++){if($y-ge$s.cells.Count-or$ci-ge$s.cells[$y].Count){break};$sp=$s.cells[$y][$ci];$cp=$cs[$ci].SelectSingleNode('./w:tcPr',$n);if(!$cp){$cp=$x.CreateElement('w','tcPr',$u);[void]$cs[$ci].PrependChild($cp)};$fill=switch($sp.style){accent{'D9EAF7'}warning{'FFF2CC'}note{'E2F0D9'}header{'D9E1F2'}default{$null}};if($fill){$sh=$x.CreateElement('w','shd',$u);$sh.SetAttribute('val',$u,'clear');$sh.SetAttribute('fill',$u,$fill);[void]$cp.AppendChild($sh)};if($sp.border-and$sp.border-ne'inherit'){$ob=$cp.SelectSingleNode('./w:tcBorders',$n);if($ob){[void]$cp.RemoveChild($ob)};if($sp.border-ne'none'){$cb=$x.CreateElement('w','tcBorders',$u);foreach($nn in @('top','left','bottom','right')){$q=$x.CreateElement('w',$nn,$u);$q.SetAttribute('val',$u,'single');$q.SetAttribute('sz',$u,$(if($sp.border-eq'thick'){'24'}else{'8'}));$q.SetAttribute('color',$u,'000000');[void]$cb.AppendChild($q)};[void]$cp.AppendChild($cb)}}}};for($yy=0;$yy-lt$s.rows;$yy++){for($xx=0;$xx-lt$s.cols;$xx++){$sp=$s.cells[$yy][$xx];if([int]$sp.rowspan-gt1-or[int]$sp.colspan-gt1){for($ry=$yy;$ry-lt$yy+[int]$sp.rowspan;$ry++){$base=$orig[$ry][$xx];$cp=$base.SelectSingleNode('./w:tcPr',$n);if(!$cp){$cp=$x.CreateElement('w','tcPr',$u);[void]$base.PrependChild($cp)};if([int]$sp.colspan-gt1){$gs=$x.CreateElement('w','gridSpan',$u);$gs.SetAttribute('val',$u,[string]$sp.colspan);[void]$cp.AppendChild($gs)};if([int]$sp.rowspan-gt1){$vm=$x.CreateElement('w','vMerge',$u);$vm.SetAttribute('val',$u,$(if($ry-eq$yy){'restart'}else{'continue'}));[void]$cp.AppendChild($vm)};for($rx=$xx+[int]$sp.colspan-1;$rx-gt$xx;$rx--){$gone=$orig[$ry][$rx];if($gone.ParentNode){[void]$gone.ParentNode.RemoveChild($gone)}}}}}};foreach($run in @($p.SelectNodes('.//w:r',$n))){$rp=$run.SelectSingleNode('./w:rPr',$n);if(!$rp){$rp=$x.CreateElement('w','rPr',$u);[void]$run.PrependChild($rp)};$vv=$x.CreateElement('w','vanish',$u);[void]$rp.AppendChild($vv)}}};
# Persist table models outside the document text in a standard OOXML custom
# document property.  Other editors may display hidden Word paragraphs, but
# custom properties never become document body text.
$records=@()
$allTables=@($x.SelectNodes('//w:tbl',$n))
foreach($mp in @($x.SelectNodes('//w:p',$n))){
 $mt=($mp.SelectNodes('.//w:t',$n)|ForEach-Object{$_.InnerText})-join''
 if($mt -match '^WORDVIM_TABLE_META_([0-9A-Fa-f]+)$'){
  $modelHex=$Matches[1];$next=$mp.NextSibling
  while($next -and $next.LocalName -ne 'tbl'){
   if($next.LocalName -eq 'p' -and (($next.SelectNodes('.//w:t',$n)|ForEach-Object{$_.InnerText})-join'').Trim() -ne ''){throw 'Table metadata is not adjacent to a table'}
   $next=$next.NextSibling
  }
  if(!$next){throw 'Table metadata has no corresponding table'}
  $index=[Array]::IndexOf($allTables,$next)
  if($index -lt 0){throw 'Cannot locate table for metadata'}
  $records+=@{index=$index;hex=$modelHex}
  [void]$mp.ParentNode.RemoveChild($mp)
 }
}
$json=if($records.Count-eq0){'[]'}else{ConvertTo-Json -InputObject @($records) -Compress}
$payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
$customNs='http://schemas.openxmlformats.org/officeDocument/2006/custom-properties'
$vtNs='http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes'
$ce=$z.GetEntry('docProps/custom.xml');$cx=New-Object Xml.XmlDocument;$cx.PreserveWhitespace=$true
if($ce){$cr=New-Object IO.StreamReader($ce.Open());$cx.LoadXml($cr.ReadToEnd());$cr.Close()}else{$root=$cx.CreateElement('Properties',$customNs);$root.SetAttribute('vt','http://www.w3.org/2000/xmlns/',$vtNs);[void]$cx.AppendChild($root)}
$cn=New-Object Xml.XmlNamespaceManager($cx.NameTable);$cn.AddNamespace('cp',$customNs);$cn.AddNamespace('vt',$vtNs)
foreach($old in @($cx.SelectNodes('/cp:Properties/cp:property[@name="WordVimTables"]',$cn))){[void]$old.ParentNode.RemoveChild($old)}
$used=@{};foreach($prop in @($cx.SelectNodes('/cp:Properties/cp:property',$cn))){$used[[int]$prop.GetAttribute('pid')]=$true};$propertyId=2;while($used.ContainsKey($propertyId)){$propertyId++}
$prop=$cx.CreateElement('property',$customNs);$prop.SetAttribute('fmtid','{D5CDD505-2E9C-101B-9397-08002B2CF9AE}');$prop.SetAttribute('pid',[string]$propertyId);$prop.SetAttribute('name','WordVimTables')
$value=$cx.CreateElement('vt','lpwstr',$vtNs);$value.InnerText=$payload;[void]$prop.AppendChild($value);[void]$cx.DocumentElement.AppendChild($prop)
if($ce){$ce.Delete()};$ce=$z.CreateEntry('docProps/custom.xml');$cw=New-Object IO.StreamWriter($ce.Open(),(New-Object Text.UTF8Encoding($false)));$cx.Save($cw);$cw.Close()
$ctEntry=$z.GetEntry('[Content_Types].xml');$ctr=New-Object IO.StreamReader($ctEntry.Open());$ctx=New-Object Xml.XmlDocument;$ctx.PreserveWhitespace=$true;$ctx.LoadXml($ctr.ReadToEnd());$ctr.Close();$ctNs='http://schemas.openxmlformats.org/package/2006/content-types';$ctn=New-Object Xml.XmlNamespaceManager($ctx.NameTable);$ctn.AddNamespace('ct',$ctNs)
if(!$ctx.SelectSingleNode('/ct:Types/ct:Override[@PartName="/docProps/custom.xml"]',$ctn)){$ov=$ctx.CreateElement('Override',$ctNs);$ov.SetAttribute('PartName','/docProps/custom.xml');$ov.SetAttribute('ContentType','application/vnd.openxmlformats-officedocument.custom-properties+xml');[void]$ctx.DocumentElement.AppendChild($ov)}
$ctEntry.Delete();$ctEntry=$z.CreateEntry('[Content_Types].xml');$ctw=New-Object IO.StreamWriter($ctEntry.Open(),(New-Object Text.UTF8Encoding($false)));$ctx.Save($ctw);$ctw.Close()
$rootRels=$z.GetEntry('_rels/.rels');$rr=New-Object IO.StreamReader($rootRels.Open());$rx=New-Object Xml.XmlDocument;$rx.PreserveWhitespace=$true;$rx.LoadXml($rr.ReadToEnd());$rr.Close();$relNs='http://schemas.openxmlformats.org/package/2006/relationships';$rn=New-Object Xml.XmlNamespaceManager($rx.NameTable);$rn.AddNamespace('r',$relNs)
if(!$rx.SelectSingleNode('/r:Relationships/r:Relationship[@Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties"]',$rn)){$ids=@{};foreach($rel0 in @($rx.DocumentElement.ChildNodes)){$ids[$rel0.GetAttribute('Id')]=$true};$ri=1;while($ids.ContainsKey('rId'+$ri)){$ri++};$rel=$rx.CreateElement('Relationship',$relNs);$rel.SetAttribute('Id','rId'+$ri);$rel.SetAttribute('Type','http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties');$rel.SetAttribute('Target','docProps/custom.xml');[void]$rx.DocumentElement.AppendChild($rel)}
$rootRels.Delete();$rootRels=$z.CreateEntry('_rels/.rels');$rw=New-Object IO.StreamWriter($rootRels.Open(),(New-Object Text.UTF8Encoding($false)));$rx.Save($rw);$rw.Close()
# Remove the incompatible v6.55 development part if a test document contains it.
$legacyPart=$z.GetEntry('word/wordvimTables.xml');if($legacyPart){$legacyPart.Delete()}
$docRels=$z.GetEntry('word/_rels/document.xml.rels');if($docRels){$dr=New-Object IO.StreamReader($docRels.Open());$dx=New-Object Xml.XmlDocument;$dx.PreserveWhitespace=$true;$dx.LoadXml($dr.ReadToEnd());$dr.Close();$changed=$false;foreach($oldRel in @($dx.DocumentElement.ChildNodes)){if($oldRel.GetAttribute('Target') -eq 'wordvimTables.xml'){[void]$dx.DocumentElement.RemoveChild($oldRel);$changed=$true}};if($changed){$docRels.Delete();$docRels=$z.CreateEntry('word/_rels/document.xml.rels');$dw=New-Object IO.StreamWriter($docRels.Open(),(New-Object Text.UTF8Encoding($false)));$dx.Save($dw);$dw.Close()}}
;$e.Delete();$e=$z.CreateEntry('word/document.xml');$w=New-Object IO.StreamWriter($e.Open(),(New-Object Text.UTF8Encoding($false)));$x.Save($w);$w.Close()}finally{$z.Dispose()}
]],path)
 local out=vim.fn.system({'powershell','-NoProfile','-ExecutionPolicy','Bypass','-Command',ps});return vim.v.shell_error==0,out
end
function M.setup()
 vim.keymap.set("n","<leader>wt",function()M.open()end,{silent=true,desc="Open Word table editor"})
 vim.api.nvim_create_user_command("WordTable",function(o)M.open(o.fargs[1],o.fargs[2])end,{nargs="*",desc="Create or edit a Word table"})end
return M
