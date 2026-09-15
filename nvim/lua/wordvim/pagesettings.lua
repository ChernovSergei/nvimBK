-- ============================================================
-- lua/wordvim/pagesettings.lua
--
-- Word page setup:
--   size, orientation, margins.
--
-- Normal mode:
--   Space p s
--
-- Command:
--   :WordPageSetup
--
-- Popup:
--   Enter / e  edit field
--   Ctrl+S     save settings to Word Vim state
--   q / Esc    cancel
--
-- The settings are written to DOCX sectPr on :w.
-- ============================================================

local M = {}

local state = {}

local NS =
  "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

local PAPER = {
  A4 = {
    portrait = { w = 11906, h = 16838 },
    landscape = { w = 16838, h = 11906 },
  },
  Letter = {
    portrait = { w = 12240, h = 15840 },
    landscape = { w = 15840, h = 12240 },
  },
  Legal = {
    portrait = { w = 12240, h = 20160 },
    landscape = { w = 20160, h = 12240 },
  },
}

local function defaults()
  return {
    size = "A4",
    orientation = "portrait",
    top = 2.54,
    bottom = 2.54,
    left = 2.54,
    right = 2.54,
  }
end

local function get_state(buf)
  if not state[buf] then
    state[buf] = defaults()
  end
  return state[buf]
end

function M.get(buf)
  return vim.deepcopy(get_state(buf))
end

function M.paper_dimensions(buf)
  local s = get_state(buf)
  local variants = PAPER[s.size] or PAPER.A4
  local dims = variants[s.orientation] or variants.portrait

  return {
    width_twips = dims.w,
    height_twips = dims.h,
    width_cm = dims.w * 2.54 / 1440,
    height_cm = dims.h * 2.54 / 1440,
    top_cm = s.top,
    bottom_cm = s.bottom,
    left_cm = s.left,
    right_cm = s.right,
  }
end

local function ps_escape(value)
  return tostring(value or ""):gsub("'", "''")
end

local function run_powershell(script)
  return require("wordvim.runtime").run_powershell(script)
end

local function twips_to_cm(value)
  return (tonumber(value) or 0) * 2.54 / 1440
end

local function cm_to_twips(value)
  return math.floor(((tonumber(value) or 0) / 2.54 * 1440) + 0.5)
end

local function fmt_cm(value)
  local text = string.format("%.2f", tonumber(value) or 0)
  text = text:gsub("0+$", ""):gsub("%.$", "")
  return text
end

local function detect_size(w, h)
  local best_name = "A4"
  local best_orientation = "portrait"
  local best_delta = math.huge

  for name, variants in pairs(PAPER) do
    for orientation, dims in pairs(variants) do
      local delta =
        math.abs((tonumber(w) or 0) - dims.w)
        + math.abs((tonumber(h) or 0) - dims.h)
      if delta < best_delta then
        best_delta = delta
        best_name = name
        best_orientation = orientation
      end
    end
  end

  return best_name, best_orientation
end

function M.load_from_docx(buf, docx)
  state[buf] = defaults()

  local temp = vim.fn.tempname() .. ".docx"
  local copied = vim.uv.fs_copyfile(docx, temp)
  if not copied then
    return
  end

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$nsUri = '%s'
$zip = $null
$reader = $null

try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zip.GetEntry('word/document.xml')

    if ($null -eq $entry) {
        exit 0
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $sectPr = $xml.SelectSingleNode('/w:document/w:body/w:sectPr', $ns)
    if ($null -eq $sectPr) {
        $sectPr = $xml.SelectSingleNode('(//w:pPr/w:sectPr)[last()]', $ns)
    }

    if ($null -eq $sectPr) {
        exit 0
    }

    $pgSz = $sectPr.SelectSingleNode('w:pgSz', $ns)
    $pgMar = $sectPr.SelectSingleNode('w:pgMar', $ns)

    $w = ''
    $h = ''
    $orient = ''
    $top = ''
    $bottom = ''
    $left = ''
    $right = ''

    if ($null -ne $pgSz) {
        $w = $pgSz.GetAttribute('w', $nsUri)
        $h = $pgSz.GetAttribute('h', $nsUri)
        $orient = $pgSz.GetAttribute('orient', $nsUri)
    }

    if ($null -ne $pgMar) {
        $top = $pgMar.GetAttribute('top', $nsUri)
        $bottom = $pgMar.GetAttribute('bottom', $nsUri)
        $left = $pgMar.GetAttribute('left', $nsUri)
        $right = $pgMar.GetAttribute('right', $nsUri)
    }

    Write-Output ($w + "`t" + $h + "`t" + $orient + "`t" + $top + "`t" + $bottom + "`t" + $left + "`t" + $right)
}
finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }
    if ($null -ne $zip) {
        $zip.Dispose()
    }
}
]], ps_escape(temp), NS)

  local ok, output = run_powershell(script)
  pcall(vim.fn.delete, temp)

  if not ok or output == "" then
    return
  end

  local line = output:match("[^\r\n]+")
  if not line then
    return
  end

  local fields = {}
  for field in (line .. "\t"):gmatch("(.-)\t") do
    table.insert(fields, field)
  end

  local w = tonumber(fields[1])
  local h = tonumber(fields[2])
  local orient = fields[3]

  if w and h then
    local size_name, detected_orientation = detect_size(w, h)
    state[buf].size = size_name
    state[buf].orientation =
      (orient == "landscape") and "landscape"
      or detected_orientation
  end

  if tonumber(fields[4]) then
    state[buf].top = twips_to_cm(fields[4])
  end
  if tonumber(fields[5]) then
    state[buf].bottom = twips_to_cm(fields[5])
  end
  if tonumber(fields[6]) then
    state[buf].left = twips_to_cm(fields[6])
  end
  if tonumber(fields[7]) then
    state[buf].right = twips_to_cm(fields[7])
  end
end

local function popup_lines(buf)
  local s = get_state(buf)

  return {
    "Page Setup",
    "",
    "Paper size:   " .. s.size,
    "Orientation:  " .. s.orientation,
    "Top margin:   " .. fmt_cm(s.top) .. " cm",
    "Bottom margin:" .. fmt_cm(s.bottom) .. " cm",
    "Left margin:  " .. fmt_cm(s.left) .. " cm",
    "Right margin: " .. fmt_cm(s.right) .. " cm",
    "",
    "Enter/e edit   Ctrl+S save   q/Esc cancel",
  }
end

local function choose_from(title, values, current, callback)
  vim.ui.select(
    values,
    {
      prompt = title,
      format_item = function(item)
        if item == current then
          return item .. "  ✓"
        end
        return item
      end,
    },
    callback
  )
end

local function edit_number(prompt, current, callback)
  vim.ui.input(
    {
      prompt = prompt,
      default = fmt_cm(current),
    },
    function(value)
      if value == nil then
        return
      end

      value = value:gsub(",", ".")
      local n = tonumber(value)

      if not n or n < 0 or n > 10 then
        vim.notify(
          "Word Vim: margin must be between 0 and 10 cm",
          vim.log.levels.WARN
        )
        return
      end

      callback(n)
    end
  )
end

function M.open()
  local source_buf = vim.api.nvim_get_current_buf()

  if not vim.b[source_buf].docx_original_file then
    vim.notify(
      "Word Vim: Page Setup is available for DOCX buffers",
      vim.log.levels.WARN
    )
    return
  end

  local original = vim.deepcopy(get_state(source_buf))
  local popup_buf = vim.api.nvim_create_buf(false, true)

  local width = 46
  local height = 10

  local win = vim.api.nvim_open_win(
    popup_buf,
    true,
    {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2 - 1),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " Word Vim ",
      title_pos = "center",
    }
  )

  vim.bo[popup_buf].modifiable = true
  vim.bo[popup_buf].buftype = "nofile"
  vim.bo[popup_buf].bufhidden = "wipe"
  vim.wo[win].cursorline = true

  local function redraw()
    if not vim.api.nvim_buf_is_valid(popup_buf) then
      return
    end

    vim.bo[popup_buf].modifiable = true
    vim.api.nvim_buf_set_lines(
      popup_buf,
      0,
      -1,
      false,
      popup_lines(source_buf)
    )
    vim.bo[popup_buf].modifiable = false
  end

  local function close(commit)
    if not commit then
      state[source_buf] = original
    else
      vim.bo[source_buf].modified = true

      local ok_pagebreaks, pagebreaks =
        pcall(require, "wordvim.pagebreaks")

      if ok_pagebreaks then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(source_buf) then
            pagebreaks.recalculate(source_buf)
          end
        end)
      end
    end

    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function edit_current()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local s = get_state(source_buf)

    if row == 3 then
      choose_from(
        "Paper size:",
        { "A4", "Letter", "Legal" },
        s.size,
        function(value)
          if value then
            s.size = value
            redraw()
          end
        end
      )
    elseif row == 4 then
      choose_from(
        "Orientation:",
        { "portrait", "landscape" },
        s.orientation,
        function(value)
          if value then
            s.orientation = value
            redraw()
          end
        end
      )
    elseif row == 5 then
      edit_number("Top margin (cm): ", s.top, function(v)
        s.top = v
        redraw()
      end)
    elseif row == 6 then
      edit_number("Bottom margin (cm): ", s.bottom, function(v)
        s.bottom = v
        redraw()
      end)
    elseif row == 7 then
      edit_number("Left margin (cm): ", s.left, function(v)
        s.left = v
        redraw()
      end)
    elseif row == 8 then
      edit_number("Right margin (cm): ", s.right, function(v)
        s.right = v
        redraw()
      end)
    end
  end

  redraw()
  vim.api.nvim_win_set_cursor(win, { 3, 0 })

  vim.keymap.set(
    "n",
    "<CR>",
    edit_current,
    { buffer = popup_buf, silent = true }
  )

  vim.keymap.set(
    "n",
    "e",
    edit_current,
    { buffer = popup_buf, silent = true }
  )

  vim.keymap.set(
    "n",
    "<C-s>",
    function()
      close(true)
    end,
    { buffer = popup_buf, silent = true }
  )

  vim.keymap.set(
    "n",
    "q",
    function()
      close(false)
    end,
    { buffer = popup_buf, silent = true }
  )

  vim.keymap.set(
    "n",
    "<Esc>",
    function()
      close(false)
    end,
    { buffer = popup_buf, silent = true }
  )
end

function M.apply_to_docx(docx, buf)
  local s = get_state(buf)
  local dims = PAPER[s.size] and PAPER[s.size][s.orientation]

  if not dims then
    dims = PAPER.A4.portrait
  end

  local path = ps_escape(docx)
  local top = cm_to_twips(s.top)
  local bottom = cm_to_twips(s.bottom)
  local left = cm_to_twips(s.left)
  local right = cm_to_twips(s.right)
  local orient = (s.orientation == "landscape") and "landscape" or ""

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$nsUri = '%s'
$pageW = '%d'
$pageH = '%d'
$orient = '%s'
$top = '%d'
$bottom = '%d'
$left = '%d'
$right = '%d'

$zipRead = $null
$reader = $null

try {
    $zipRead = [System.IO.Compression.ZipFile]::OpenRead($path)
    $entry = $zipRead.GetEntry('word/document.xml')

    if ($null -eq $entry) {
        throw 'word/document.xml not found'
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $zipRead) { $zipRead.Dispose() }
}

$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('w', $nsUri)

$body = $xml.SelectSingleNode('/w:document/w:body', $ns)
$sectPr = $body.SelectSingleNode('w:sectPr', $ns)

if ($null -eq $sectPr) {
    $sectPr = $xml.CreateElement('w', 'sectPr', $nsUri)
    [void]$body.AppendChild($sectPr)
}

$pgSz = $sectPr.SelectSingleNode('w:pgSz', $ns)
if ($null -eq $pgSz) {
    $pgSz = $xml.CreateElement('w', 'pgSz', $nsUri)
    [void]$sectPr.PrependChild($pgSz)
}

[void]$pgSz.SetAttribute('w', $nsUri, $pageW)
[void]$pgSz.SetAttribute('h', $nsUri, $pageH)

if ($orient -eq 'landscape') {
    [void]$pgSz.SetAttribute('orient', $nsUri, 'landscape')
}
else {
    [void]$pgSz.RemoveAttribute('orient', $nsUri)
}

$pgMar = $sectPr.SelectSingleNode('w:pgMar', $ns)
if ($null -eq $pgMar) {
    $pgMar = $xml.CreateElement('w', 'pgMar', $nsUri)
    [void]$sectPr.AppendChild($pgMar)
}

[void]$pgMar.SetAttribute('top', $nsUri, $top)
[void]$pgMar.SetAttribute('bottom', $nsUri, $bottom)
[void]$pgMar.SetAttribute('left', $nsUri, $left)
[void]$pgMar.SetAttribute('right', $nsUri, $right)

# Preserve header/footer/gutter values if they exist. If absent, add Word-like defaults.
if (-not $pgMar.HasAttribute('header', $nsUri)) {
    [void]$pgMar.SetAttribute('header', $nsUri, '720')
}
if (-not $pgMar.HasAttribute('footer', $nsUri)) {
    [void]$pgMar.SetAttribute('footer', $nsUri, '720')
}
if (-not $pgMar.HasAttribute('gutter', $nsUri)) {
    [void]$pgMar.SetAttribute('gutter', $nsUri, '0')
}

$newXml = $xml.DocumentElement.OuterXml

$fileStream = $null
$zipUpdate = $null
$writer = $null

try {
    $fileStream = [System.IO.File]::Open(
        $path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )

    $zipUpdate = New-Object System.IO.Compression.ZipArchive(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Update,
        $false
    )

    $oldEntry = $zipUpdate.GetEntry('word/document.xml')
    $oldEntry.Delete()

    $newEntry = $zipUpdate.CreateEntry(
        'word/document.xml',
        [System.IO.Compression.CompressionLevel]::Optimal
    )

    $writer = New-Object System.IO.StreamWriter(
        $newEntry.Open(),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $writer.Write($newXml)
    $writer.Flush()
}
finally {
    if ($null -ne $writer) { $writer.Dispose() }
    if ($null -ne $zipUpdate) { $zipUpdate.Dispose() }
    if ($null -ne $fileStream) { $fileStream.Dispose() }
}
]],
    path,
    NS,
    dims.w,
    dims.h,
    orient,
    top,
    bottom,
    left,
    right
  )

  local ok, output = run_powershell(script)

  if not ok then
    vim.notify(
      "Word Vim: could not apply Page Setup:\n" .. output,
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

function M.attach(buf)
  vim.keymap.set(
    "n",
    "<leader>ps",
    M.open,
    {
      buffer = buf,
      silent = true,
      desc = "Word Vim: Page Setup",
    }
  )
end

function M.detach(buf)
  state[buf] = nil
end

function M.setup()
  vim.api.nvim_create_user_command(
    "WordPageSetup",
    M.open,
    {
      desc = "Word Vim page setup",
    }
  )
end

return M
