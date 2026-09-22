vim.opt.rtp:prepend(vim.fn.getcwd())
local stopped=false
vim.lsp.semantic_tokens.stop=function(buf,id) stopped=buf==vim.api.nvim_get_current_buf() and id==99 end
local client={id=99,server_capabilities={semanticTokensProvider={},diagnosticProvider={}}}
require('plugins.java').on_attach(client,vim.api.nvim_get_current_buf())
assert(stopped and not client.server_capabilities.semanticTokensProvider)
assert(client.server_capabilities.diagnosticProvider)
local config
package.loaded.conform={setup=function(c) config=c end}
require('plugins.conform')
assert(config.formatters['google-java-format'].prepend_args[1]=='--aosp')
require('core.idea_colors').setup()
assert(vim.api.nvim_get_hl(0,{name='@keyword.modifier.java'}).fg==0xCF8E6D)
print('PASS Java semantic-color opt-out preserves diagnostics, four-space formatter option and keyword colors')
vim.cmd('qa!')
