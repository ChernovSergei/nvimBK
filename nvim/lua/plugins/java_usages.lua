local M={}
function M.open(choices,title,on_select)
  local pickers=require('telescope.pickers')
  local finders=require('telescope.finders')
  local conf=require('telescope.config').values
  local actions=require('telescope.actions')
  local state=require('telescope.actions.state')
  local entries={}
  for _,choice in ipairs(choices) do
    local item=vim.lsp.util.locations_to_items({choice.location},choice.encoding)[1]
    if item then
      item.choice=choice
      entries[#entries+1]=item
    end
  end
  local opts={}
  pickers.new(opts,{
    prompt_title=title,
    finder=finders.new_table({results=entries,entry_maker=function(item)
      local display=(item.filename or '')..':'..item.lnum..': '..(item.text or '')
      return {value=item,display=display,ordinal=display,filename=item.filename,
        bufnr=item.bufnr,lnum=item.lnum,col=item.col}
    end}),
    sorter=conf.generic_sorter(opts),previewer=conf.qflist_previewer(opts),
    attach_mappings=function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry=state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then on_select(entry.value.choice) end
      end)
      return true
    end,
  }):find()
end
return M
