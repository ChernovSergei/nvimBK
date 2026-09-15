-- IntelliJ-inspired editor palette, approximated from the supplied screenshot.
local M = {}
function M.apply()
  local p={bg='#191A1C',fg='#BCBEC4',keyword='#CF8E6D',method='#56A8F5',field='#C77DBB',string='#6AAB73',comment='#7A7E85',annotation='#BBB529'}
  local function hl(names, spec)
    for name in names:gmatch('%S+') do vim.api.nvim_set_hl(0,name,spec) end
  end
  hl('Normal NormalNC', {fg=p.fg,bg=p.bg})
  hl('NormalFloat Pmenu', {fg=p.fg,bg='#232428'})
  hl('CursorLine', {bg='#26282D'})
  hl('Visual PmenuSel', {bg='#35435D'})
  hl('LineNr', {fg='#60656F',bg=p.bg})
  hl('CursorLineNr', {fg=p.fg,bg='#26282D'})
  hl('SignColumn FoldColumn', {fg='#60656F',bg=p.bg})
  hl('ColorColumn', {bg='#26282D'})
  hl('Comment @comment @comment.java @comment.documentation @comment.documentation.java @lsp.type.comment @lsp.type.comment.java javaComment javaLineComment javaDocComment javaCommentTitle javaDocTags javaDocParam', {fg=p.comment,italic=false})
  hl('Keyword Statement Conditional Repeat Exception Include StorageClass Boolean @keyword @boolean', {fg=p.keyword,bold=false,italic=false})
  hl('Type Identifier @type @variable @variable.parameter @lsp.type.class @lsp.type.interface @lsp.type.parameter @lsp.type.variable', {fg=p.fg,bold=false,italic=false})
  hl('Function @function @function.method @lsp.type.method @lsp.type.function', {fg=p.method,bold=false,italic=false})
  hl('@variable.member @lsp.type.property', {fg=p.field})
  hl('String Character @string @character', {fg=p.string})
  hl('Number Float @number', {fg='#2AACB8'})
  hl('Operator Delimiter @operator @punctuation', {fg=p.fg})
  hl('PreProc @attribute @lsp.type.decorator', {fg=p.annotation})
  hl('javaStatement javaConditional javaRepeat javaExceptions javaStorageClass javaScopeDecl javaExternal javaBoolean javaType @variable.builtin.java @type.builtin.java @keyword.java', {fg=p.keyword})
  hl('javaAnnotation @attribute.java', {fg=p.annotation})
  hl('@lsp.type.property.java @variable.member.java', {fg=p.field})
  hl('@lsp.type.method.java @function.method.java @function.java', {fg=p.method})
  hl('javaDocComment javaCommentTitle javaDocTags javaDocParam @comment.documentation.java', {fg='#629755',italic=false})
  hl('@lsp.mod.static.java', {italic=false})
end
function M.setup()
  local group=vim.api.nvim_create_augroup('WordVimIdeaColors',{clear=true})
  vim.api.nvim_create_autocmd('ColorScheme',{group=group,callback=M.apply})
  M.apply()
  -- GUI clients can use this; terminal clients choose fonts in their own settings.
  vim.o.guifont='JetBrains Mono:h14'
end
return M


