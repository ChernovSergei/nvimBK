local M={}
local function key(path) local p=vim.fs.normalize(path):gsub('\\','/'); return vim.fn.has('win32')==1 and p:lower() or p end
function M.apply(edit,encoding)
  local renamed={}
  -- Preflight resource operations before any text changes.
  for _,change in ipairs(edit.documentChanges or {}) do
    if change.kind then
      assert(change.kind=='rename','Unsupported rename resource operation: '..change.kind)
      local old,new=vim.uri_to_fname(change.oldUri),vim.uri_to_fname(change.newUri)
      assert(change.oldUri:match('^file:') and change.newUri:match('^file:'),'Only local Java files can be renamed')
      assert(vim.uv.fs_stat(old),'Rename source does not exist: '..old)
      assert(key(vim.fs.dirname(old))==key(vim.fs.dirname(new)), 'Refusing class rename outside its package directory')
      assert(not (vim.uv.fs_stat(new) and key(old)~=key(new)), 'Rename target already exists: '..new)
      for _,buf in ipairs(vim.api.nvim_list_bufs()) do
        assert(key(old)==key(new) or key(vim.api.nvim_buf_get_name(buf))~=key(new),
          'Rename target already has an open buffer: '..new)
      end
    end
  end
  if edit.changes then vim.lsp.util.apply_workspace_edit({changes=edit.changes},encoding) end
  for _,change in ipairs(edit.documentChanges or {}) do
    if change.kind=='rename' then
      local old,new=vim.uri_to_fname(change.oldUri),vim.uri_to_fname(change.newUri)
      local buffers={}
      for _,buf in ipairs(vim.api.nvim_list_bufs()) do
        if key(vim.api.nvim_buf_get_name(buf))==key(old) then buffers[#buffers+1]=buf end
      end
      local ok,err=vim.uv.fs_rename(old,new); assert(ok,err)
      for _,buf in ipairs(buffers) do
        vim.api.nvim_buf_set_name(buf,new)
        renamed[#renamed+1]=buf
      end
    else
      vim.lsp.util.apply_text_document_edit(change,nil,encoding)
    end
  end
  -- :file/set_name marks a buffer as not yet written under its new name.
  -- Write the renamed file once to clear E13, after all ordered text edits.
  -- The destination was checked above and was created by our fs_rename.
  for _,buf in ipairs(renamed) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_call(buf,function()vim.cmd('silent keepalt write!')end)
    end
  end
end
function M.rename()
  local buf,win=vim.api.nvim_get_current_buf(),vim.api.nvim_get_current_win()
  local client=vim.lsp.get_clients({bufnr=buf,name='jdtls'})[1]
  if not client then vim.notify('JDTLS not connected',vim.log.levels.WARN);return end
  local params=vim.lsp.util.make_position_params(win,client.offset_encoding)
  vim.ui.input({prompt='Rename Java symbol: ',default=vim.fn.expand('<cword>')},function(name)
    if not name or name=='' then return end
    params.newName=name
    client:request('textDocument/rename',params,function(err,edit)
      if err then
        vim.schedule(function()
          vim.notify('Java rename cancelled: '..err.message..'\nFix errors first; no rename was applied.',vim.log.levels.WARN)
          if vim.api.nvim_win_is_valid(win) and #vim.diagnostic.get(buf,{severity=vim.diagnostic.severity.ERROR})>0 then
            vim.api.nvim_win_call(win,function()vim.diagnostic.setloclist({open=true,severity=vim.diagnostic.severity.ERROR})end)
          end
        end)
        return
      end
      if not edit then return end
      local ok,message=pcall(M.apply,edit,client.offset_encoding)
      vim.notify(ok and 'Java renamed. Use :wa to save all changed files.' or tostring(message),ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    end,buf)
  end)
end
function M.template()
  if vim.bo.filetype~='java' or vim.api.nvim_buf_line_count(0)~=1 or vim.api.nvim_get_current_line()~='' then return end
  local path=vim.api.nvim_buf_get_name(0):gsub('\\','/')
  local name=path:match('/([^/]+)%.java$')
  if not name or not name:match('^[%a_$][%w_$]*$') then return end
  local package=path:match('/src/main/java/(.*)/[^/]+$') or path:match('/src/test/java/(.*)/[^/]+$')
  local lines={}
  if package and package~='' then lines={'package '..package:gsub('/','.')..';',''} end
  vim.list_extend(lines,{'public class '..name..' {','','}'})
  vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
end
return M
