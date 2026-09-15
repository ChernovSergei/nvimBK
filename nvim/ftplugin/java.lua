local java = require('plugins.java')
local bufnr = vim.api.nvim_get_current_buf()
java.setup_buffer(bufnr)
local function start()
  local root = require('jdtls.setup').find_root({
    'mvnw', 'gradlew', 'pom.xml', 'build.gradle', 'build.gradle.kts',
    'settings.gradle', 'settings.gradle.kts', '.git',
  })
  root = root or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  if not root or root == '' then error('Save the Java file before starting JDTLS') end
  local config, err = require('plugins.java_launch').build(root)
  if not config then error(err) end
  config.capabilities = require('cmp_nvim_lsp').default_capabilities()
  config.on_attach = java.on_attach
  require('jdtls').start_or_attach(config)
end
local ok, err = pcall(start)
if not ok then
  vim.b[bufnr].wordvim_java_error = tostring(err)
  -- ERROR notifications inside FileType can propagate through :edit/Neo-tree.
  -- Report after opening the buffer; keep the failure available in status.
  vim.schedule(function()
    vim.notify('WordVim Java: ' .. tostring(err), vim.log.levels.WARN)
  end)
end
