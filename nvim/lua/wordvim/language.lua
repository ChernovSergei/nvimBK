-- ============================================================
-- lua/wordvim/language.lua
-- Word Vim language integration: spell checking, Windows input layout,
-- statusline indicator, and DOCX proofing language (w:lang).
-- v6.19: global Neovim input-layout switching, matching the VibreOffice workflow.
-- While editing in Insert mode the user may change the Windows layout normally.
-- On InsertLeave Word Vim remembers that real Windows layout, then restores EN.
-- On the next InsertEnter it restores the remembered layout.  Layout changes are
-- scheduled after mode transitions. Cursor-shape handling is intentionally
-- separate in wordvim/cursor.lua. DOCX proofing language remains separate.
-- ============================================================

local M = {}

local specs = {
  en = {
    code = "en",
    label = "EN",
    name = "English",
    spell = "en_us",
    word = "en-US",
    klid = "00000409",
  },
  ru = {
    code = "ru",
    label = "RU",
    name = "Russian",
    spell = "ru_ru",
    word = "ru-RU",
    klid = "00000419",
  },
  ro = {
    code = "ro",
    label = "RO",
    name = "Romanian",
    spell = "ro",
    word = "ro-RO",
    klid = "00000418",
  },
}

local aliases = {
  ["en"] = "en", ["en-us"] = "en", ["en-gb"] = "en", ["english"] = "en",
  ["ru"] = "ru", ["ru-ru"] = "ru", ["russian"] = "ru",
  ["ro"] = "ro", ["ro-ro"] = "ro", ["romanian"] = "ro",
}

local function is_wordvim_docx(buf)
  return buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].wordvim_docx == true
end

local function normalize_code(value)
  if not value or value == "" then
    return nil
  end
  local key = tostring(value):lower():gsub("_", "-")
  if aliases[key] then
    return aliases[key]
  end
  local prefix = key:match("^([a-z][a-z])")
  if prefix and specs[prefix] then
    return prefix
  end
  return nil
end

local function set_spell_for_buffer(buf, spec)
  -- 'spelllang' is buffer-local; 'spell' is window-local.
  pcall(vim.api.nvim_set_option_value, "spelllang", spec.spell, { buf = buf })

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    pcall(vim.api.nvim_set_option_value, "spell", true, { win = win })
  end
end

local ffi_backend = nil
local ffi_user32 = nil

local function init_ffi_backend()
  if ffi_backend ~= nil then
    return ffi_backend
  end

  ffi_backend = false
  if vim.fn.has("win32") ~= 1 and vim.fn.has("win64") ~= 1 then
    return false
  end

  local ok, ffi = pcall(require, "ffi")
  if not ok then
    return false
  end

  pcall(ffi.cdef, [[
    typedef void* HWND;
    typedef void* HKL;
    typedef unsigned int UINT;
    typedef unsigned long WPARAM;
    typedef long LPARAM;
    typedef unsigned long DWORD;
    HKL LoadKeyboardLayoutW(const wchar_t* pwszKLID, UINT Flags);
    HWND GetForegroundWindow(void);
    DWORD GetWindowThreadProcessId(HWND hWnd, DWORD* lpdwProcessId);
    HKL GetKeyboardLayout(DWORD idThread);
    int PostMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
  ]])

  local ok_user32, user32 = pcall(ffi.load, "user32")
  if not ok_user32 then
    return false
  end

  ffi_backend = ffi
  ffi_user32 = user32
  return ffi_backend
end

local function utf16_buffer(ffi, text)
  -- KLIDs are ASCII hex strings, so a tiny UTF-16LE buffer is sufficient.
  local buf = ffi.new("wchar_t[?]", #text + 1)
  for i = 1, #text do
    buf[i - 1] = text:byte(i)
  end
  buf[#text] = 0
  return buf
end

local function switch_windows_layout_powershell(spec)
  local shell = require("wordvim.runtime").powershell()
  if not shell then return end
  local script = string.format([[
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WordVimKeyboard {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern IntPtr LoadKeyboardLayout(string pwszKLID, uint Flags);
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]
  public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
'@
$hkl = [WordVimKeyboard]::LoadKeyboardLayout('%s', 1)
$hwnd = [WordVimKeyboard]::GetForegroundWindow()
if ($hkl -eq [IntPtr]::Zero -or $hwnd -eq [IntPtr]::Zero) { exit 2 }
[void][WordVimKeyboard]::PostMessage($hwnd, 0x0050, [IntPtr]::Zero, $hkl)
]], spec.klid)

  if vim.system then
    vim.system({ shell, "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script }, { text = true }, function() end)
  else
    vim.fn.jobstart({ shell, "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script }, { detach = true })
  end
end

local function switch_windows_layout(spec)
  if vim.g.wordvim_switch_windows_layout == false then
    return
  end
  if vim.fn.has("win32") ~= 1 and vim.fn.has("win64") ~= 1 then
    return
  end

  -- Fast path: call user32 directly from Neovim.  This avoids spawning a
  -- PowerShell process on every InsertEnter/InsertLeave, so the layout changes
  -- before the user starts typing.
  local ffi = init_ffi_backend()
  if ffi and ffi_user32 then
    local klid = utf16_buffer(ffi, spec.klid)
    local hkl = ffi_user32.LoadKeyboardLayoutW(klid, 1)
    local hwnd = ffi_user32.GetForegroundWindow()
    if hkl ~= nil and hwnd ~= nil then
      -- WM_INPUTLANGCHANGEREQUEST = 0x0050
      local ok = ffi_user32.PostMessageW(hwnd, 0x0050, 0, ffi.cast("LPARAM", hkl))
      if ok ~= 0 then
        return
      end
    end
  end

  -- Fallback for builds where LuaJIT FFI is unavailable.
  switch_windows_layout_powershell(spec)
end

local function normal_layout_spec()
  local code = normalize_code(vim.g.wordvim_normal_mode_language) or "en"
  return specs[code] or specs.en
end

local function switch_to_normal_layout()
  switch_windows_layout(normal_layout_spec())
end

local global_input_spec

-- Read the layout that Windows is actually using in the foreground window.
-- This is what lets the user press Win+Space / Alt+Shift manually while typing
-- and have Word Vim remember that choice for the next Insert session.
local function current_windows_layout_code()
  local ffi = init_ffi_backend()
  if not ffi or not ffi_user32 then
    return nil
  end

  local hwnd = ffi_user32.GetForegroundWindow()
  if hwnd == nil then
    return nil
  end

  local thread_id = ffi_user32.GetWindowThreadProcessId(hwnd, nil)
  if thread_id == 0 then
    return nil
  end

  local hkl = ffi_user32.GetKeyboardLayout(thread_id)
  if hkl == nil then
    return nil
  end

  -- The low word of HKL is the Windows LANGID.  Convert the pointer-sized
  -- handle through intptr_t; LuaJIT provides intptr_t as a standard C type.
  local ok_num, raw = pcall(function()
    return tonumber(ffi.cast("intptr_t", hkl))
  end)
  if not ok_num or not raw then
    return nil
  end

  local langid = raw % 0x10000
  if langid == 0x0409 then return "en" end
  if langid == 0x0419 then return "ru" end
  if langid == 0x0418 then return "ro" end
  return nil
end

local layout_sync_generation = 0

local function mode_uses_insert_layout(mode)
  mode = tostring(mode or "")
  local first = mode:sub(1, 1)
  return first == "i" or first == "R"
end

-- Never switch the OS layout directly from InsertEnter/InsertLeave.  In some
-- terminal/Windows combinations that can race Neovim's own mode/cursor update.
-- Run after the mode transition and re-check the ACTUAL mode before switching.
local function schedule_mode_layout_sync(delay_ms)
  layout_sync_generation = layout_sync_generation + 1
  local generation = layout_sync_generation

  local function run()
    if generation ~= layout_sync_generation then
      return
    end

    local mode = vim.api.nvim_get_mode().mode
    if mode_uses_insert_layout(mode) then
      local _, spec = global_input_spec()
      switch_windows_layout(spec)
    else
      switch_to_normal_layout()
    end

    vim.schedule(function()
      pcall(vim.cmd, "redrawstatus")
    end)
  end

  if (delay_ms or 0) > 0 then
    vim.defer_fn(run, delay_ms)
  else
    vim.schedule(run)
  end
end

local function remember_current_insert_layout()
  local code = current_windows_layout_code()
  if code and specs[code] then
    vim.g.wordvim_insert_language = code
    vim.cmd("redrawstatus")
    return code
  end
  return nil
end

global_input_spec = function()
  local code = normalize_code(vim.g.wordvim_insert_language)
    or normalize_code(vim.g.wordvim_default_input_language)
    or "en"
  return code, specs[code] or specs.en
end

function M.input_current()
  return global_input_spec()
end

function M.input_status()
  -- Show the language that is active for the CURRENT Neovim mode, not merely
  -- the language remembered for the next Insert session.  This keeps the
  -- Word Vim statusline consistent with the Windows taskbar: Normal = EN,
  -- Insert/Replace = remembered Insert layout.
  local mode = vim.api.nvim_get_mode().mode
  if mode_uses_insert_layout(mode) then
    local _, spec = global_input_spec()
    return spec and spec.label or "--"
  end

  local spec = normal_layout_spec()
  return spec and spec.label or "EN"
end

function M.set_input(code, opts)
  opts = opts or {}
  code = normalize_code(code)
  local spec = code and specs[code] or nil
  if not spec then
    if not opts.silent then
      vim.notify("Word Vim input language: supported values are EN, RU, RO", vim.log.levels.ERROR)
    end
    return false
  end

  vim.g.wordvim_insert_language = code

  -- The selected Insert language is persistent.  Apply it according to the
  -- actual mode after the current key/event has finished.
  schedule_mode_layout_sync(0)

  if not opts.silent then
    vim.notify(string.format("Input language: %s (Insert); EN in Normal", spec.name), vim.log.levels.INFO)
  end
  vim.cmd("redrawstatus")
  return true
end

function M.current(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local code = normalize_code(vim.b[buf].wordvim_language) or "en"
  return code, specs[code]
end

function M.status(buf)
  local _, spec = M.current(buf)
  return spec and spec.label or "--"
end

function M.set(buf, code, opts)
  buf = buf or vim.api.nvim_get_current_buf()
  opts = opts or {}

  if not is_wordvim_docx(buf) then
    if not opts.silent then
      vim.notify("Word Vim language: current buffer is not a DOCX", vim.log.levels.WARN)
    end
    return false
  end

  code = normalize_code(code)
  local spec = code and specs[code] or nil
  if not spec then
    if not opts.silent then
      vim.notify("Word Vim language: supported values are EN, RU, RO", vim.log.levels.ERROR)
    end
    return false
  end

  vim.b[buf].wordvim_language = code
  set_spell_for_buffer(buf, spec)

  if opts.switch_layout ~= false then
    -- Normal mode is intentionally kept in English (or the configured
    -- normal-mode layout).  Selecting RU/RO in Normal mode only selects the
    -- language that will be activated on the next InsertEnter.
    schedule_mode_layout_sync(0)
  end

  -- Changing proofing language is a document change because save writes w:lang.
  if opts.mark_modified ~= false then
    vim.bo[buf].modified = true
  end

  if not opts.silent then
    vim.notify(
      string.format("Word Vim language: %s (%s)", spec.name, spec.word),
      vim.log.levels.INFO
    )
  end

  vim.cmd("redrawstatus")
  return true
end

local function ps_single_quote(value)
  return "'" .. tostring(value):gsub("'", "''") .. "'"
end

function M.detect_from_docx(path)
  if not path or path == "" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local script = string.format([[
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$path = %s
$zip = [System.IO.Compression.ZipFile]::OpenRead($path)
try {
  $parts = @('word/document.xml', 'word/styles.xml')
  foreach ($part in $parts) {
    $entry = $zip.GetEntry($part)
    if ($null -eq $entry) { continue }
    $reader = New-Object System.IO.StreamReader($entry.Open())
    try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($xmlText -match '<w:lang[^>]*w:val="([^"]+)"') {
      Write-Output $Matches[1]
      exit 0
    }
  }
} finally {
  $zip.Dispose()
}
]], ps_single_quote(path))

  local ok, out = require("wordvim.runtime").run_powershell(script)
  if not ok then
    return nil
  end

  local value = tostring(out):gsub("[%s\r\n]+$", "")
  return normalize_code(value)
end

function M.load_from_docx(buf, path)
  if not is_wordvim_docx(buf) then
    return
  end

  local code = M.detect_from_docx(path) or normalize_code(vim.g.wordvim_default_language) or "en"
  M.set(buf, code, {
    silent = true,
    switch_layout = false,
    mark_modified = false,
  })
end

function M.apply_to_docx(path, buf)
  if not path or path == "" then
    return false
  end

  local _, spec = M.current(buf)
  if not spec then
    return true
  end

  local script = string.format([[
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = %s
$lang = %s
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

function Update-XmlPart([string]$partName, [scriptblock]$mutator) {
  $zipRead = [System.IO.Compression.ZipFile]::OpenRead($path)
  try {
    $entry = $zipRead.GetEntry($partName)
    if ($null -eq $entry) { return }
    $reader = New-Object System.IO.StreamReader($entry.Open())
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally {
    $zipRead.Dispose()
  }

  $xml = New-Object System.Xml.XmlDocument
  $xml.PreserveWhitespace = $true
  $xml.LoadXml($text)
  $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $nsmgr.AddNamespace('w', $nsUri)

  & $mutator $xml $nsmgr

  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
  $settings.Indent = $false
  $settings.OmitXmlDeclaration = $false
  $sw = New-Object System.IO.StringWriter
  $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
  $xml.Save($xw)
  $xw.Flush(); $xw.Close()
  $newText = $sw.ToString()
  # StringWriter reports UTF-16 in the declaration; DOCX XML is UTF-8.
  $newText = $newText -replace 'encoding="utf-16"', 'encoding="UTF-8"'

  $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
  try {
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Update, $false)
    try {
      $old = $zip.GetEntry($partName)
      if ($null -ne $old) { $old.Delete() }
      $new = $zip.CreateEntry($partName, [System.IO.Compression.CompressionLevel]::Optimal)
      $writer = New-Object System.IO.StreamWriter($new.Open(), (New-Object System.Text.UTF8Encoding($false)))
      try { $writer.Write($newText) } finally { $writer.Dispose() }
    } finally {
      $zip.Dispose()
    }
  } finally {
    $fs.Dispose()
  }
}

Update-XmlPart 'word/document.xml' {
  param($xml, $nsmgr)
  $runs = $xml.SelectNodes('//w:r', $nsmgr)
  foreach ($r in $runs) {
    $rPr = $r.SelectSingleNode('./w:rPr', $nsmgr)
    if ($null -eq $rPr) {
      $rPr = $xml.CreateElement('w', 'rPr', $nsUri)
      if ($r.HasChildNodes) { [void]$r.InsertBefore($rPr, $r.FirstChild) }
      else { [void]$r.AppendChild($rPr) }
    }
    $langNode = $rPr.SelectSingleNode('./w:lang', $nsmgr)
    if ($null -eq $langNode) {
      $langNode = $xml.CreateElement('w', 'lang', $nsUri)
      [void]$rPr.AppendChild($langNode)
    }
    $langNode.SetAttribute('val', $nsUri, $lang)
  }
}

Update-XmlPart 'word/styles.xml' {
  param($xml, $nsmgr)
  $styles = $xml.DocumentElement
  if ($null -eq $styles) { return }
  $docDefaults = $styles.SelectSingleNode('./w:docDefaults', $nsmgr)
  if ($null -eq $docDefaults) {
    $docDefaults = $xml.CreateElement('w', 'docDefaults', $nsUri)
    if ($styles.HasChildNodes) { [void]$styles.InsertBefore($docDefaults, $styles.FirstChild) }
    else { [void]$styles.AppendChild($docDefaults) }
  }
  $rPrDefault = $docDefaults.SelectSingleNode('./w:rPrDefault', $nsmgr)
  if ($null -eq $rPrDefault) {
    $rPrDefault = $xml.CreateElement('w', 'rPrDefault', $nsUri)
    [void]$docDefaults.AppendChild($rPrDefault)
  }
  $rPr = $rPrDefault.SelectSingleNode('./w:rPr', $nsmgr)
  if ($null -eq $rPr) {
    $rPr = $xml.CreateElement('w', 'rPr', $nsUri)
    [void]$rPrDefault.AppendChild($rPr)
  }
  $langNode = $rPr.SelectSingleNode('./w:lang', $nsmgr)
  if ($null -eq $langNode) {
    $langNode = $xml.CreateElement('w', 'lang', $nsUri)
    [void]$rPr.AppendChild($langNode)
  }
  $langNode.SetAttribute('val', $nsUri, $lang)
}
]], ps_single_quote(path), ps_single_quote(spec.word))

  local ok, out = require("wordvim.runtime").run_powershell(script)
  if not ok then
    vim.notify("Word Vim language: failed to write DOCX w:lang:\n" .. tostring(out), vim.log.levels.ERROR)
    return false
  end

  return true
end

function M.attach(buf)
  if not is_wordvim_docx(buf) then
    return
  end

  -- DOCX proofing is per document. Keyboard layout switching is global and
  -- is installed once from setup(), so opening/closing a DOCX does not create
  -- buffer-local InsertEnter/InsertLeave handlers.
  local _, spec = M.current(buf)
  set_spell_for_buffer(buf, spec)
end

function M.setup()
  if vim.g.wordvim_default_language == nil then
    vim.g.wordvim_default_language = "en"
  end
  if vim.g.wordvim_default_input_language == nil then
    vim.g.wordvim_default_input_language = "en"
  end
  if vim.g.wordvim_insert_language == nil then
    vim.g.wordvim_insert_language = vim.g.wordvim_default_input_language
  end
  if vim.g.wordvim_switch_windows_layout == nil then
    vim.g.wordvim_switch_windows_layout = true
  end
  if vim.g.wordvim_normal_mode_language == nil then
    vim.g.wordvim_normal_mode_language = "en"
  end
  -- Global input-layout behaviour for ALL Neovim buffers:
  --   Insert mode -> globally selected EN/RU/RO
  --   Normal mode -> English
  local group = vim.api.nvim_create_augroup("WordVimGlobalInputLanguage", { clear = true })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
      -- Restore the language remembered from the previous Insert session.
      -- Scheduling avoids racing the terminal cursor-shape transition.
      schedule_mode_layout_sync(0)
    end,
    desc = "Word Vim global input: restore remembered Insert layout",
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      -- Capture what Windows is REALLY using before we force Normal mode to EN.
      -- Thus a manual Win+Space/Alt+Shift change made while typing is remembered.
      remember_current_insert_layout()

      -- Give Neovim/terminal a moment to finish changing the cursor to Normal
      -- mode before posting WM_INPUTLANGCHANGEREQUEST.
      schedule_mode_layout_sync(12)

      -- Refresh the statusline immediately: it must show EN in Normal mode even
      -- though the remembered Insert language may still be RU/RO.
      vim.schedule(function()
        vim.cmd("redrawstatus")
      end)
    end,
    desc = "Word Vim global input: remember Insert layout, then restore EN",
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FocusGained" }, {
    group = group,
    callback = function()
      schedule_mode_layout_sync(0)
    end,
    desc = "Word Vim global input: keep Windows layout synchronized with mode",
  })

  -- Global mappings: these select the language used on the next InsertEnter.
  local mapopts = { silent = true }
  vim.keymap.set("n", "<leader>le", function() M.set_input("en") end, vim.tbl_extend("force", mapopts, { desc = "Input language: English" }))
  vim.keymap.set("n", "<leader>lr", function() M.set_input("ru") end, vim.tbl_extend("force", mapopts, { desc = "Input language: Russian" }))
  vim.keymap.set("n", "<leader>lo", function() M.set_input("ro") end, vim.tbl_extend("force", mapopts, { desc = "Input language: Romanian" }))

  _G.WordVimLanguageStatus = function()
    return M.input_status()
  end

  -- Global input-layout commands.
  vim.api.nvim_create_user_command("WordInputLanguage", function(args)
    M.set_input(args.args)
  end, {
    nargs = 1,
    complete = function() return { "en", "ru", "ro" } end,
    desc = "Set global Insert-mode input language: en, ru, ro",
  })
  vim.api.nvim_create_user_command("WordInputEnglish", function() M.set_input("en") end, {})
  vim.api.nvim_create_user_command("WordInputRussian", function() M.set_input("ru") end, {})
  vim.api.nvim_create_user_command("WordInputRomanian", function() M.set_input("ro") end, {})

  -- DOCX proofing language remains separate and per document.
  vim.api.nvim_create_user_command("WordLanguage", function(args)
    M.set(vim.api.nvim_get_current_buf(), args.args, { switch_layout = false })
  end, {
    nargs = 1,
    complete = function() return { "en", "ru", "ro" } end,
    desc = "Set current DOCX proofing language: en, ru, ro",
  })

  vim.api.nvim_create_user_command("WordLanguageEnglish", function() M.set(vim.api.nvim_get_current_buf(), "en", { switch_layout = false }) end, {})
  vim.api.nvim_create_user_command("WordLanguageRussian", function() M.set(vim.api.nvim_get_current_buf(), "ru", { switch_layout = false }) end, {})
  vim.api.nvim_create_user_command("WordLanguageRomanian", function() M.set(vim.api.nvim_get_current_buf(), "ro", { switch_layout = false }) end, {})

  -- setup() normally runs in Normal mode.  Synchronize after startup rather
  -- than posting a Windows message from inside setup().
  schedule_mode_layout_sync(0)
end

return M
