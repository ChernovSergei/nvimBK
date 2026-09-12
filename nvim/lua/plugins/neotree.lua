vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])

vim.fn.sign_define("DiagnosticSignError", { text = " ", texthl = "DiagnosticSignError" })
vim.fn.sign_define("DiagnosticSignWarn", { text = " ", texthl = "DiagnosticSignWarn" })
vim.fn.sign_define("DiagnosticSignInfo", { text = " ", texthl = "DiagnosticSignInfo" })
vim.fn.sign_define("DiagnosticSignHint", { text = "󰌵", texthl = "DiagnosticSignHint" })

local function wordvim_images()
  local ok, images = pcall(require, "wordvim.images")
  if ok then
    return images
  end
  return nil
end

local function normal_command(state, name)
  if state and state.commands and state.commands[name] then
    state.commands[name](state)
    return true
  end
  return false
end

require("neo-tree").setup({
  filesystem = {
    window = {
      mappings = {
        ["<CR>"] = function(state)
          local images = wordvim_images()
          if images and images.neotree_select_node and images.neotree_select_node(state) then
            return
          end
          normal_command(state, "open")
        end,

        ["q"] = function(state)
          local images = wordvim_images()
          if images and images.neotree_picker_active and images.neotree_picker_active() then
            images.cancel_neotree_picker(false)
          end
          if not normal_command(state, "close_window") then
            pcall(vim.cmd, "close")
          end
        end,

        ["<Esc>"] = function(state)
          local images = wordvim_images()
          if images and images.neotree_picker_active and images.neotree_picker_active() then
            images.cancel_neotree_picker(false)
            if not normal_command(state, "close_window") then
              pcall(vim.cmd, "close")
            end
          end
        end,
      },
    },
  },
})
