local M = {}
local win, buf, origin, origin_mode, origin_cursor
local prompt_modifiable
local command_window
local last_source
local sections = {}
local function valid(w) return w and vim.api.nvim_win_is_valid(w) end
local function close()
  local w, source, mode = win, origin, origin_mode
  win, buf, origin = nil, nil, nil
  if valid(w) then vim.api.nvim_win_close(w, true) end
  if valid(source) then
    if command_window == source then
      vim.bo[vim.api.nvim_win_get_buf(source)].modifiable=prompt_modifiable
      command_window = nil
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-c>',true,false,true),'n',false)
    else
      vim.api.nvim_set_current_win(source)
      if mode == 'i' then
        vim.api.nvim_win_set_cursor(source,origin_cursor)
        local line=vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(source),origin_cursor[1]-1,origin_cursor[1],false)[1] or ''
        vim.cmd(origin_cursor[2]>=#line and 'startinsert!' or 'startinsert')
      elseif mode == 't' then vim.cmd('startinsert') end
    end
  end
end
local function geometry()
  return {relative='editor', row=0, col=0, width=math.max(1,vim.o.columns),
    height=math.max(1,vim.o.lines-vim.o.cmdheight), style='minimal', border='none', zindex=250}
end
local function context(b)
  local ft = vim.bo[b].filetype
  if ft == 'wordvim-table' then return 'DOCX TABLE', b end
  if vim.fn.getcmdwintype() ~= '' then
    for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local candidate=vim.api.nvim_win_get_buf(w)
      if vim.bo[candidate].filetype=='wordvim-table' then return 'DOCX TABLE',candidate end
    end
  end
  if vim.b[b].wordvim_docx or vim.b[b].docx_original_file then return 'DOCX', b end
  if ft:match('^wordvim') or ft:match('^WordVim') then return 'DOCX', b end
  if vim.bo[b].buftype ~= '' and last_source and vim.api.nvim_buf_is_valid(last_source) then
    b = last_source; ft = vim.bo[b].filetype
    if vim.b[b].wordvim_docx or vim.b[b].docx_original_file then return 'DOCX', b end
  end
  if ft == 'java' then return 'JAVA', b end
  if ft:match('^javascript') or ft:match('^typescript') then return 'NODE.JS', b end
  local path = vim.api.nvim_buf_get_name(b)
  local root = path ~= '' and vim.fn.fnamemodify(path, ':p:h') or vim.fn.getcwd()
  local markers = vim.fs.find({'package.json','pom.xml','build.gradle','build.gradle.kts','mvnw','gradlew'}, {path=root, upward=true})
  if markers[1] then return vim.fn.fnamemodify(markers[1], ':t') == 'package.json' and 'NODE.JS' or 'JAVA', b end
  return 'FILES', b
end
local table_rows = {
  'h/j/k/l / arrows       Move between cells',
  'w / Tab; b / Shift+Tab Next / previous cell',
  'Enter                 Edit selected cell',
  'Space then M          Mark anchor, move, merge rectangle',
  'U                     Split merged cell',
  'S / B / L             Cell style / cell borders / table borders',
  'H                     Set number of header rows',
  'A / D                 Append row / delete selected row',
  'I / X                 Insert column / delete column',
  'R                     Delete existing table (confirmation)',
  'W                     Apply table changes; :w in DOCX saves file',
  'Q / q                 Close without applying table changes',
  'F1 / ?                Global help',
}
local java_rows = {
  ':WordJavaStatus       Show JDTLS connection / startup error',
  'Space ja / jr         Java code action / rename (JDTLS attached)',
  'Space jc              Generate constructors',
  'Space je / jt         Generate hashCode/equals / toString',
  'Space jm / jg         Override methods / generate getters',
  'Space ji              Organize imports',
  'Space gi / gi         Implementation in a new tab (Enter to select)',
  'gt                    Type definition',
  'Space gr / gr / Space ju  Telescope usages; Enter opens a new tab',
  'Space tt / tn         Test class / nearest method (java-test)',
  'Space f               Format Java (google-java-format or LSP)',
  ':terminal mvn test    Run Maven tests (Maven project)',
  ':terminal ./gradlew test  Run Gradle tests (Linux wrapper)',
}
local node_rows = {
  'K / gD                Hover / declaration (LSP attached)',
  'Space rn / ca         Rename / code action (LSP attached)',
  'Space d               Show diagnostic at cursor',
  'Space f               Format JS/TS using Prettier or LSP',
  ':terminal npm run     List package.json scripts',
  ':terminal npm test    Run test script if defined',
  ':terminal npm run dev Run dev script if defined',
  ':terminal node file.js Run JavaScript file',
}
local nvim_rows = {
  'Neo-tree zO           Expand all subfolders of selected folder',
  'Neo-tree zM           Collapse all folders',
  'Alt+Left / Alt+Right  Previous / next tab',
  'F1                    Toggle fullscreen global help (all modes)',
  'Space wh / :WordHelp  Toggle global help',
  'Enter / double-click Follow selected contents entry',
  'Tab / Shift+Tab       Next / previous contents entry',
  'gO / Backspace        Return to contents',
  '1 / 2 / 3 / 4        Jump to help section',
  'q / Esc / F1          Close help and return to source window',
  '/text; n / N          Search help; next / previous match',
  'j/k; Ctrl+d / Ctrl+u  Scroll help',
  'i / a / Esc           Insert / append / Normal mode',
  ':w / :q / :wq        Save / close / save and close',
  'u / Ctrl+r            Undo / redo',
  'yy / dd / p           Copy line / delete line / paste',
  'v / V / Ctrl+v        Character / line / block selection',
  'Ctrl+c; Ctrl+v        Clipboard copy (Normal/Visual); paste (Normal/Insert)',
  'Ctrl+s                Save in Insert mode',
  'Ctrl+w h/j/k/l        Focus adjacent split',
  'Ctrl+n                New vertical split (Normal)',
  'Alt+Left / Alt+Right  Previous / next tab',
  ':terminal             Open terminal',
  'Ctrl+\\ Ctrl+n        Leave terminal input mode',
  'Space e / o           Neo-tree files / Git status',
  'Neo-tree: ?           List actual Neo-tree mappings',
  'Space ff / fg / fb    Telescope files / live grep (rg) / buffers',
  'Space fh              Telescope Neovim help tags',
  'Space gb / gc / gs    Telescope Git branches / commits / status',
  'Space ls; gd / gr     LSP document symbols; definitions / references',
  ':Inspect / :InspectTree Tree-sitter captures / syntax tree',
  ':TSUpdate             Update installed Tree-sitter parsers',
  ':Mason                Manage language servers and tools',
  ':Lazy                 Manage configured plugins',
  ':checkhealth          Diagnose Neovim and plugins',
  ':WordHealth           Check Windows/Linux/proot dependencies',
  ':Copy                 Copy entire buffer to system clipboard',
  ':ConformInfo          Show formatter availability',
  'Insert: Ctrl+Space    nvim-cmp completion (code buffers)',
  'Insert: Enter / Ctrl+e Accept / dismiss completion',
  'Insert: Ctrl+b / Ctrl+f Scroll completion documentation',
  ':lua require("luasnip").jump(1) Next snippet field',
  ':lua require("luasnip").jump(-1) Previous snippet field',
  'F7 / F8 / Shift+F8 / F9 DAP into / over / out / continue (adapter required)',
  'Space b               DAP breakpoint (Normal; DOCX Visual = bold)',
  ':lua require("dapui").toggle() Toggle debugger panels',
  ':lua require("nvim-autopairs").toggle() Toggle automatic pairs',
  ':help nvim-ts-autotag  Help for automatic HTML/JSX closing tags',
  ':colorscheme tokyonight Apply configured theme',
}
local linux_rows = {
  'pwd / ls -la          Show directory / list files including hidden',
  'cd PATH / cd ..       Change directory / parent directory',
  'mkdir -p PATH         Create directories',
  'cp -r SRC DST         Copy file or directory',
  'mv SRC DST            Move or rename',
  'rm -i FILE            Delete file with confirmation',
  'cat FILE / less FILE  Print / browse text',
  'head -n 20 FILE       First 20 lines',
  'tail -f FILE          Follow appended log lines',
  'find . -name "*.java" Find matching files',
  'grep -n TEXT FILE     Find text with line numbers',
  'rg TEXT / rg --files  Search project / list files (ripgrep)',
  'command -v NAME       Locate command',
  'man NAME / NAME --help Command documentation',
  'ps aux / kill PID     List processes / request termination',
  'df -h / du -sh PATH   Disk space / directory size',
  'chmod +x FILE         Make executable',
  'export NAME=value     Set environment variable in shell',
  'CMD > FILE / CMD | less Redirect output / page output',
  'git status / git diff Inspect changes',
  'git log --oneline     Show commit history',
  'git add FILE          Stage file',
  'git commit -m "text"  Commit staged changes',
  'git fetch             Fetch remote refs',
  './mvnw test / ./gradlew test Run Java wrapper tests',
  'npm run / npm test    List scripts / run test script',
}
local powershell_rows = {
  'Get-Location / Get-ChildItem -Force Show directory / files',
  'Set-Location PATH     Change directory',
  'New-Item PATH -ItemType Directory Create directory',
  'Copy-Item -LiteralPath SRC -Destination DST -Recurse Copy',
  'Move-Item -LiteralPath SRC -Destination DST Move',
  'Remove-Item -LiteralPath FILE -Confirm Delete with confirmation',
  'Get-Content -LiteralPath FILE Read text',
  'Get-Content FILE -Tail 20 -Wait Follow log',
  'Select-String -Path *.java -Pattern TEXT Search text',
  'Get-Command NAME      Locate command',
  'Get-Help NAME -Examples Show command examples',
  'Get-Process           List processes',
  'Stop-Process -Id PID -Confirm Terminate process with confirmation',
  'Get-ChildItem | Where-Object Extension -eq .js Filter objects',
  'Get-ChildItem | Select-Object Name,Length Select properties',
  '$env:NAME = "value"   Set environment variable for session',
  '& "C:\\path\\tool.exe" Run program at quoted path',
  'Compress-Archive -Path SRC -DestinationPath OUT.zip Create ZIP',
  'Expand-Archive -LiteralPath IN.zip -DestinationPath DIR Extract ZIP',
  '.\\mvnw.cmd test / .\\gradlew.bat test Run Java wrapper tests',
  'npm.cmd run / npm.cmd test List / run npm scripts',
  'git status / git diff Inspect repository changes',
}
function M.open()
  if valid(win) then close(); return end
  origin, origin_mode = vim.api.nvim_get_current_win(), vim.fn.mode():sub(1,1)
  origin_cursor = vim.api.nvim_win_get_cursor(origin)
  local kind, source = context(vim.api.nvim_get_current_buf())
  local lines, entries = {}, {}
  local function section(title, rows)
    sections[#sections+1] = #lines+1
    entries[#entries+1] = {label=title, target=#lines+1}
    lines[#lines+1] = title
    for i,line in ipairs(rows) do
      if line:match('^[A-Z][A-Z /%-()]+$') and (rows[i+1] or ''):match('^%-%-+') then
        entries[#entries+1] = {label='    '..line, target=#lines+1}
      end
      lines[#lines+1] = line
    end
    lines[#lines+1] = ''
  end
  sections = {}
  local rows = kind == 'JAVA' and java_rows or kind == 'NODE.JS' and node_rows
    or kind == 'DOCX TABLE' and table_rows or kind == 'DOCX' and require('wordvim.helpdata').docx()
    or {':edit FILE            Open file', ':terminal             Open project shell'}
  rows = vim.deepcopy(rows)
  -- Include effective buffer-local mappings, including future installed modules.
  for _,mode in ipairs({'n','i','x'}) do
    for _,m in ipairs(vim.api.nvim_buf_get_keymap(source,mode)) do
      if m.desc and m.desc ~= '' then rows[#rows+1] = mode .. ': ' .. m.lhs .. '  ' .. m.desc end
    end
  end
  section('1. PROJECT: '..kind, rows)
  section('2. NEOVIM / PLUGINS', nvim_rows)
  section('3. LINUX SHELL', linux_rows)
  section('4. POWERSHELL', powershell_rows)
  local contents = {'WORDVIM HELP - CONTENTS / СОДЕРЖАНИЕ',
    'Enter: open | Tab/Shift+Tab: select | gO/Backspace: contents | F1: close', ''}
  local links, toc_rows = {}, {}
  local offset = #contents + #entries + 1
  for _,entry in ipairs(entries) do
    contents[#contents+1] = entry.label
    links[#contents] = entry.target + offset
    toc_rows[#toc_rows+1] = #contents
  end
  contents[#contents+1] = ''
  for i,row in ipairs(sections) do sections[i] = row + offset end
  vim.list_extend(contents,lines)
  lines = contents
  buf = vim.api.nvim_create_buf(false,true)
  vim.bo[buf].bufhidden='wipe'; vim.bo[buf].filetype='wordvimhelp'
  vim.api.nvim_buf_set_lines(buf,0,-1,false,lines)
  vim.bo[buf].modifiable=false
  local in_prompt = vim.fn.getcmdwintype() ~= ''
  win = vim.api.nvim_open_win(buf,not in_prompt,geometry())
  local keybuf = in_prompt and vim.api.nvim_get_current_buf() or buf
  vim.wo[win].wrap=true; vim.wo[win].linebreak=true; vim.wo[win].cursorline=true
  if origin_mode == 'i' or origin_mode == 't' then vim.cmd('stopinsert') end
  for _,key in ipairs({'q','<Esc>','<F1>','<leader>wh'}) do
    vim.keymap.set('n',key,close,{buffer=keybuf,silent=true,nowait=true})
  end
  if in_prompt then
    prompt_modifiable=vim.bo[keybuf].modifiable
    vim.bo[keybuf].modifiable=false
    for key,delta in pairs({j=1,k=-1,['<Down>']=1,['<Up>']=-1,['<C-d>']=12,['<C-u>']=-12}) do
      vim.keymap.set('n',key,function()
        local row=vim.api.nvim_win_get_cursor(win)[1]
        vim.api.nvim_win_set_cursor(win,{math.max(1,math.min(#lines,row+delta)),0})
      end,{buffer=keybuf,silent=true})
    end
  end
  local function jump(row)
    vim.api.nvim_win_set_cursor(win,{row,0})
    if not in_prompt then
      vim.api.nvim_win_call(win,function()
        if links[row] then vim.fn.winrestview({topline=1}) else vim.cmd('normal! zt') end
      end)
    end
  end
  local function follow()
    local target=links[vim.api.nvim_win_get_cursor(win)[1]]
    if target then jump(target) end
  end
  local opts={buffer=keybuf,silent=true,nowait=true}
  vim.keymap.set('n','<CR>',follow,opts)
  vim.keymap.set('n','<2-LeftMouse>',function()
    local pos=vim.fn.getmousepos()
    if pos.winid==win and pos.line>0 then
      vim.api.nvim_win_set_cursor(win,{pos.line,0}); follow()
    end
  end,opts)
  for _,key in ipairs({'gO','<BS>'}) do
    vim.keymap.set('n',key,function() jump(toc_rows[1]) end,opts)
  end
  for key,delta in pairs({['<Tab>']=1,['<S-Tab>']=-1}) do
    vim.keymap.set('n',key,function()
      local current=vim.api.nvim_win_get_cursor(win)[1]
      local index=delta==1 and 1 or #toc_rows
      for i,row in ipairs(toc_rows) do
        if row==current then index=((i-1+delta)%#toc_rows)+1; break end
      end
      jump(toc_rows[index])
    end,opts)
  end
  for row in pairs(links) do vim.api.nvim_buf_add_highlight(buf,-1,'Underlined',row-1,0,-1) end
  vim.api.nvim_win_set_cursor(win,{toc_rows[1],0})
  for i,row in ipairs(sections) do
    vim.keymap.set('n',tostring(i),function() vim.api.nvim_win_set_cursor(win,{row,0}); if not in_prompt then vim.api.nvim_win_call(win,function() vim.cmd('normal! zt') end) end end,{buffer=keybuf})
    vim.api.nvim_buf_add_highlight(buf,-1,'Title',row-1,0,-1)
  end
end
function M.attach() end -- Global mappings cover every document and popup.
function M.setup()
  vim.keymap.set({'n','i','x','s','o','t'},'<F1>',M.open,{silent=true,desc='Global fullscreen help'})
  vim.keymap.set('c','<F1>',function()
    vim.api.nvim_create_autocmd('CmdwinEnter',{once=true,callback=function()
      command_window=vim.api.nvim_get_current_win()
      M.open()
    end})
    return '<C-f>'
  end,{expr=true,silent=true,desc='Global fullscreen help (preserve prompt)'})
  vim.keymap.set('n','<leader>wh',M.open,{silent=true,desc='Global fullscreen help'})
  vim.api.nvim_create_user_command('WordHelp',M.open,{desc='Global fullscreen help'})
  local group=vim.api.nvim_create_augroup('WordVimGlobalHelp',{clear=true})
  vim.api.nvim_create_autocmd('BufEnter',{group=group,callback=function(ev)
    if vim.bo[ev.buf].buftype=='' then last_source=ev.buf end
  end})
  vim.api.nvim_create_autocmd('VimResized',{group=group,callback=function()
    if valid(win) then vim.api.nvim_win_set_config(win,geometry()) end
  end})
end
return M





