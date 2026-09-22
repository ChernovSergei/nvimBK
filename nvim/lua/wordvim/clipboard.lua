local M={}
local function write(path,data)
 local fd,err=vim.uv.fs_open(path,'w',384);assert(fd,err)
 assert(vim.uv.fs_write(fd,data,0));vim.uv.fs_close(fd)
end
local function insert(lines) require('wordvim.tables').insert_fragment(lines) end
function M.file(path)
 assert(vim.b.wordvim_docx,'Open a DOCX document first')
 path=vim.fn.fnamemodify(path,':p')
 local ext=path:match('%.([^%.]+)$');ext=ext and ext:lower()
 local media=vim.fn.tempname()..'_wordvim_paste';vim.fn.mkdir(media,'p')
 if ({png=true,jpg=true,jpeg=true,gif=true,bmp=true,webp=true})[ext] then
  local target=media..'/image.'..ext;assert(vim.uv.fs_copyfile(path,target))
  insert({'![]('..'<'..vim.fs.normalize(target)..'>'..')'})
  return
 end
 assert(vim.fn.executable('pandoc')==1,'Pandoc is required')
 local filter=vim.api.nvim_get_runtime_file('tools/paste-tables.lua',false)[1]
 assert(filter,'WordVim paste-tables.lua is missing')
 local result=vim.system({'pandoc',path,'--lua-filter='..filter,'--to=markdown+pipe_tables-grid_tables-simple_tables-multiline_tables-smart','--wrap=none','--extract-media='..media},{text=true}):wait()
 assert(result.code==0,result.stderr)
 local lines=require('wordvim.paragraphs').normalize_import(vim.split(result.stdout,'\n',{plain=true}))
 insert(require('wordvim.lists').to_editor_lines(lines))
end
function M.paste()
 assert(vim.b.wordvim_docx,'Open a DOCX document first')
 local rt=require('wordvim.runtime')
 if rt.windows() then
  local base=vim.fn.tempname()
  local path=base:gsub("'","''")
  local ok,result=rt.run_powershell(([=[
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WordVimHtmlClipboard {
 [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr owner);
 [DllImport("user32.dll")] static extern bool CloseClipboard();
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
 [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
 [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr handle);
 [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr handle);
 [DllImport("kernel32.dll")] static extern UIntPtr GlobalSize(IntPtr handle);
 public static string Read() {
  if (!OpenClipboard(IntPtr.Zero)) throw new Exception("Clipboard is busy; copy and paste again.");
  try {
   IntPtr h=GetClipboardData(RegisterClipboardFormat("HTML Format"));
   if(h==IntPtr.Zero) throw new Exception("HTML clipboard unavailable.");
   IntPtr p=GlobalLock(h);
   if(p==IntPtr.Zero) throw new Exception("Cannot read HTML clipboard.");
   try {
    byte[] bytes=new byte[checked((int)GlobalSize(h).ToUInt64())];
    Marshal.Copy(p,bytes,0,bytes.Length);
    int length=Array.IndexOf(bytes,(byte)0);
    return new UTF8Encoding(false,true).GetString(bytes,0,length<0?bytes.Length:length);
   } finally {GlobalUnlock(h);}
  } finally {CloseClipboard();}
 }
}
'@
$p='%s'
if([Windows.Forms.Clipboard]::ContainsData('HTML Format')) {
 $html=[WordVimHtmlClipboard]::Read()
 $start=$html.IndexOf('<!--StartFragment-->');$end=$html.IndexOf('<!--EndFragment-->')
 if($start -ge 0 -and $end -gt $start){$html=$html.Substring($start+20,$end-$start-20)}
 else {$start=$html.IndexOf('<');if($start -ge 0){$html=$html.Substring($start)}}
 # Fragment extraction removes the source charset declaration. Explicitly
 # declare UTF-8 so the HTML reader cannot reinterpret its bytes as Latin-1.
 $html='<html><head><meta charset="utf-8"></head><body>'+$html+'</body></html>'
 [IO.File]::WriteAllText($p+'.html',$html,(New-Object Text.UTF8Encoding($false)))
 Write-Output ($p+'.html')
} elseif([Windows.Forms.Clipboard]::ContainsImage()) {
 $image=[Windows.Forms.Clipboard]::GetImage()
 try {$image.Save($p+'.png',[Drawing.Imaging.ImageFormat]::Png)} finally {$image.Dispose()}
 Write-Output ($p+'.png')
} else {
 [IO.File]::WriteAllText($p+'.txt',[Windows.Forms.Clipboard]::GetText(),(New-Object Text.UTF8Encoding($false)))
 Write-Output ($p+'.txt')
}
]=]):format(path),true)
  assert(ok,result)
  local file=vim.trim(result)
  if file:match('%.txt$') then insert(vim.fn.readfile(file)) else M.file(file) end
  vim.fn.delete(file)
  return
 end
 -- Desktop Linux exposes typed clipboard content; proot without a display
 -- falls back to the configured Neovim/Termux text clipboard provider.
 local tool=vim.fn.executable('wl-paste')==1 and 'wl-paste' or (vim.fn.executable('xclip')==1 and 'xclip' or nil)
 if tool then
  for _,kind in ipairs({'text/html','image/png'}) do
   local args=tool=='wl-paste' and {tool,'--no-newline','--type',kind} or {tool,'-selection','clipboard','-o','-t',kind}
   local result=vim.system(args):wait()
   if result.code==0 and result.stdout and #result.stdout>0 then
    local path=vim.fn.tempname()..(kind=='text/html' and '.html' or '.png');write(path,result.stdout);M.file(path);vim.fn.delete(path);return
   end
  end
 end
 local text=vim.fn.getreg('+')
 assert(text~='','Clipboard is empty or unavailable. Use :WordInsertFile instead.')
 insert(vim.split(text,'\n',{plain=true}))
end
function M.setup()
 local function safe(fn) return function(o)local ok,err=pcall(fn,o);if not ok then vim.notify(tostring(err),vim.log.levels.ERROR)end end end
 vim.api.nvim_create_user_command('WordPaste',safe(M.paste),{})
 vim.api.nvim_create_user_command('WordInsertFile',safe(function(o)M.file(o.args)end),{nargs=1,complete='file'})
 vim.keymap.set('n','<leader>wp',safe(M.paste),{desc='Paste rich clipboard into DOCX'})
end
return M
