-- Application-wide panel palette. No document data or DOCX properties are stored here.
local M = {}
local cached, cached_path
local function path() return vim.fn.stdpath('state')..'/wordvim/panel-colors.json' end
local function key(name) return vim.trim(tostring(name or '')):gsub('%s+',' '):lower() end
local function read_file(p)
  local value=vim.json.decode(table.concat(vim.fn.readfile(p),'\n'))
  assert(type(value)=='table','Invalid panel palette: '..p)
  local result={}
  for name,color in pairs(value) do
    if type(name)=='string' and type(color)=='string' and color:match('^%x%x%x%x%x%x$') then
      result[key(name)]=color:upper()
    end
  end
  return result
end
local function read()
  local p=path()
  if cached and cached_path==p then return cached end
  local result={}
  if vim.fn.filereadable(p)==1 then
    result=read_file(p)
  else
    -- v6_59 stored overrides per document. Merge once into the application
    -- palette; the most recently edited file wins when a style has conflicts.
    local legacy=vim.fn.glob(vim.fn.stdpath('state')..'/wordvim/panel-colors/*.json',false,true)
    table.sort(legacy,function(a,b)
      local ta,tb=vim.fn.getftime(a),vim.fn.getftime(b)
      return ta==tb and a<b or ta<tb
    end)
    for _,old in ipairs(legacy) do
      local ok,values=pcall(read_file,old)
      if ok then for name,color in pairs(values) do result[name]=color end end
    end
  end
  cached,cached_path=result,p
  return result
end
function M.get(_,name)
  local ok,values=pcall(read)
  return ok and values[key(name)] or ''
end
function M.hue(name)
  -- Stable across documents even when the style list has a different order.
  return tonumber(vim.fn.sha256(key(name)):sub(1,6),16)%360
end
function M.set(_,name,value)
  value=vim.trim(value or ''):gsub('^#',''):upper()
  if value~='' and not value:match('^%x%x%x%x%x%x$') then
    return false,'Panel color must be blank or six HEX digits (e.g. 1F4E79)'
  end
  local p=path()
  local ok,err=pcall(function()
    -- Reload so another Neovim instance's saved changes are not discarded.
    cached=nil
    local data=vim.deepcopy(read())
    data[key(name)]=value~='' and value or nil
    vim.fn.mkdir(vim.fn.fnamemodify(p,':h'),'p')
    local temp=p..'.'..vim.fn.getpid()..'.tmp'
    assert(vim.fn.writefile({vim.json.encode(data)},temp)==0,'Cannot write panel colors')
    assert(vim.fn.rename(temp,p)==0,'Cannot replace panel colors')
    cached,cached_path=data,p
  end)
  if ok then
    vim.api.nvim_exec_autocmds('User',{pattern='WordVimPanelColorsChanged',modeline=false})
  end
  return ok,err
end
function M.invalidate() cached=nil end
return M
