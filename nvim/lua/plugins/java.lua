local M = {}

-- === Safe Java code-action selector (title-based) ===
local function java_action_by_title(pattern)
  vim.lsp.buf.code_action({
    apply = true,
    filter = function(action)
      return action.title and action.title:match(pattern)
    end,
  })
end

function M.status(bufnr)
  if #vim.lsp.get_clients({bufnr = bufnr, name = 'jdtls'}) > 0 then
    return 'JDTLS connected; leader = Space'
  end
  return 'JDTLS not connected: ' .. (vim.b[bufnr].wordvim_java_error or 'starting or exited; see :messages and :LspLog')
end

function M.setup_buffer(bufnr)
  local opts = { buffer = bufnr, silent = true, noremap = true }
  local function map(mode, key, action, options)
    vim.keymap.set(mode, key, function()
      if #vim.lsp.get_clients({bufnr = bufnr, name = 'jdtls'}) == 0 then
        vim.notify('WordVim Java: ' .. M.status(bufnr), vim.log.levels.WARN)
        return
      end
      action()
    end, options)
  end
  vim.api.nvim_buf_create_user_command(bufnr, 'WordJavaStatus', function()
    vim.notify(M.status(bufnr))
  end, {force = true})

  vim.api.nvim_buf_create_user_command(bufnr,'JavaClass',function() require('plugins.java_edit').template() end,{force=true})
  -- General
  map('n', 'K', vim.lsp.buf.hover, opts)
  map('n', 'gD', vim.lsp.buf.declaration, opts)
  map('n', 'gd', vim.lsp.buf.definition, opts)
  map('n', 'gr', require('plugins.java_navigation').references, opts)
  map('n', '<leader>rn', require('plugins.java_edit').rename, opts)
  map({'n', 'v'}, '<leader>ca', vim.lsp.buf.code_action, opts)
  vim.keymap.set('n', '<leader>d', vim.diagnostic.open_float, opts)
  map({ "n", "v" }, "<leader>ja", function()
  if vim.fn.mode() == "v" or vim.fn.mode() == "V" then
    vim.lsp.buf.code_action()
  else
    vim.lsp.buf.code_action()
  end
  end, opts)
  map("n", "<leader>jr", require('plugins.java_edit').rename, opts)

  -- Code generation
  map("n", "<leader>jc", function()
    java_action_by_title("^Generate Constructors")
  end, opts)

  map("n", "<leader>je", function()
    java_action_by_title("hashCode")
  end, opts)

  map("n", "<leader>jt", function()
    java_action_by_title("toString")
  end, opts)

  map("n", "<leader>jm", function()
    java_action_by_title("Override")
  end, opts)

  -- Imports
  map("n", "<leader>ji", function()
    java_action_by_title("Organize imports")
  end, opts)

  map("n", "<leader>jg", function()
    java_action_by_title("getter")
  end, opts)

  -- Extract refactorings
--  map("n", "<leader>em", vim.lsp.buf.extract_method, opts)
--  map("n", "<leader>ev", vim.lsp.buf.extract_variable, opts)
--  map("n", "<leader>ec", vim.lsp.buf.extract_constant, opts)

  --Navigation
  map("n", "gi", require("plugins.java_navigation").implementation, opts)
  map("n", "<leader>gi", require("plugins.java_navigation").implementation, opts)
  map("n", "<leader>gr", require("plugins.java_navigation").references, opts)
  map("n", "gt", vim.lsp.buf.type_definition, opts)

  --Usage
  map("n", "<leader>ju",
    require("plugins.java_navigation").references, opts)

  -- Tests (jdtls helpers are stable here)
  local jdtls = setmetatable({}, {__index = function(_, name) return function() require("jdtls")[name]() end end})
  map("n", "<leader>tt", jdtls.test_class, opts)
  map("n", "<leader>tn", jdtls.test_nearest_method, opts)
end

function M.on_attach(client, bufnr)
  -- Prefer locally updated syntax colors while editing. LSP diagnostics remain enabled.
  if vim.g.wordvim_java_semantic_colors ~= true and client.server_capabilities then
    client.server_capabilities.semanticTokensProvider = nil
    if client.id then pcall(vim.lsp.semantic_tokens.stop, bufnr, client.id) end
  end
  vim.b[bufnr].wordvim_java_error = nil
  M.setup_buffer(bufnr)
end

return M




