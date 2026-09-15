local M = {}
local function navigate(method, title, always_select)
  local source=vim.api.nvim_get_current_win()
  local bufnr=vim.api.nvim_get_current_buf()
  vim.lsp.buf_request_all(bufnr,method,function(client)
    local params=vim.lsp.util.make_position_params(source,client.offset_encoding)
    if method=='textDocument/references' then params.context={includeDeclaration=false} end
    return params
  end,function(results)
    if not vim.api.nvim_win_is_valid(source) or vim.api.nvim_win_get_buf(source)~=bufnr then return end
    local choices={}
    for id,response in pairs(results) do
      local client=vim.lsp.get_client_by_id(id)
      if response.error or response.err then
        local err=response.error or response.err
        vim.notify(title..': '..(err.message or tostring(err)),vim.log.levels.WARN)
      elseif client and response.result then
        local locations=vim.islist(response.result) and response.result or {response.result}
        for _,location in ipairs(locations) do
          choices[#choices+1]={location=location,encoding=client.offset_encoding}
        end
      end
    end
    local function open(choice)
      if not choice or not vim.api.nvim_win_is_valid(source) then return end
      vim.api.nvim_set_current_win(source)
      -- Never interpolate a URI into an Ex command: %, #, spaces and | are data.
      vim.cmd('tab split')
      local target=vim.api.nvim_get_current_win()
      local ok,shown=pcall(vim.lsp.util.show_document,choice.location,choice.encoding,{focus=true,reuse_win=false})
      if not ok or not shown then
        if vim.api.nvim_win_is_valid(target) then vim.api.nvim_win_close(target,true) end
        vim.notify(title..': '..(ok and 'Cannot open location' or tostring(shown)),vim.log.levels.WARN)
      end
    end
    if #choices==0 then
      vim.notify('No results: '..title,vim.log.levels.INFO)
    elseif always_select then
      require('plugins.java_usages').open(choices,title,open)
    elseif #choices==1 then open(choices[1])
    else
      vim.ui.select(choices,{prompt=title,format_item=function(choice)
        local l=choice.location
        local uri=l.uri or l.targetUri
        local range=l.range or l.targetSelectionRange or l.targetRange
        return uri..':'..(range.start.line+1)
      end},open)
    end
  end)
end
function M.implementation()
  navigate('textDocument/implementation','Java implementations',false)
end
function M.references()
  navigate('textDocument/references','Java usages',true)
end
return M


