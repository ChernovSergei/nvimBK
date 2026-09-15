local M = {}
function M.label(buf)
  local name=vim.api.nvim_buf_get_name(buf):gsub('\\','/')
  if name=='' then return '[No Name]' end
  local tail=name:match('([^/]+)$') or name
  if tail:match('%.java$') then
    local parent=name:match('([^/]+)/[^/]+$')
    if parent then return parent..'/'..tail end
  end
  return tail
end
function M.render()
  local parts={}
  for i,tab in ipairs(vim.api.nvim_list_tabpages()) do
    local win=vim.api.nvim_tabpage_get_win(tab)
    local buf=vim.api.nvim_win_get_buf(win)
    local label=M.label(buf):gsub('%%','%%%%')
    local modified=false
    for _,w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].modified then modified=true end
    end
    parts[#parts+1]='%'..i..'T'..(tab==vim.api.nvim_get_current_tabpage() and '%#TabLineSel#' or '%#TabLine#')..' '..label..(modified and ' +' or '')..' '
  end
  return table.concat(parts)..'%#TabLineFill#%T%='
end
function M.setup()
  vim.o.tabline="%!v:lua.require'core.tablabels'.render()"
end
return M
