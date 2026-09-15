-- ============================================================
-- lua/wordvim/docx.lua
--
-- DOCX open/save layer.
--
-- Important design choices:
-- 1. Neovim buffer shows clean Markdown/text.
-- 2. Paragraph styles are hidden in wordvim.styles.
-- 3. styles.xml is read from a TEMPORARY DOCX COPY to avoid
--    Windows file-lock conflicts while Neovim opens the file.
-- ============================================================

local M = {}

local styles = require("wordvim.styles")
local paragraphs = require("wordvim.paragraphs")
local indents = require("wordvim.indents")
local lists = require("wordvim.lists")
local pagebreaks = require("wordvim.pagebreaks")
local pagesettings = require("wordvim.pagesettings")
local toc = require("wordvim.toc")
local crossrefs = require("wordvim.crossrefs")
local language = require("wordvim.language")
local formatting = require("wordvim.formatting")
local images = require("wordvim.images")
local styleui = require("wordvim.styleui")
local help = require("wordvim.help")
local tables = require("wordvim.tables")

local group = vim.api.nvim_create_augroup("WordVimDocx", { clear = true })
local window_restore = {}

local markdown_format =
  "markdown"
  .. "+bracketed_spans"
  .. "+fenced_divs"
  .. "+strikeout"
  .. "+pipe_tables"
  -- Word Vim edits tables as compact pipe-table rows. Pandoc's default
  -- Markdown writer prefers grid/simple tables when reading DOCX, which
  -- makes a table expand into many ordinary editor lines on reopen.
  -- Disable the alternative table syntaxes so DOCX -> Markdown remains
  -- stable as a pipe table across save/open cycles.
  .. "-grid_tables"
  .. "-simple_tables"
  .. "-multiline_tables"
  .. "+raw_html"

-- A temporary text token used only while converting DOCX <-> Markdown.
-- It makes a real, empty Word paragraph visible to Pandoc so Word Vim can
-- distinguish it from Markdown separator blank lines.  The token is never
-- left in the user's DOCX: it is removed from document.xml before save.
local EMPTY_PARAGRAPH_MARKER = "WORDVIM_EMPTY_PARAGRAPH_7D4E91C2"
local INLINE_TAB_MARKER = "WORDVIM_INLINE_TAB_5F83A1D4"
local HEADING_MARKER_PREFIX = "WORDVIM_HEADING_7D4E91C2_L"


local function ps_escape(value)
  return tostring(value or ""):gsub("'", "''")
end

local function run_powershell(script)
  local output = vim.fn.system({
    "powershell",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    script,
  })

  return vim.v.shell_error == 0, output
end

local function copy_file(src, dst)
  local ok, result, err = pcall(vim.uv.fs_copyfile, src, dst)
  if not ok or not result then
    return false, tostring(err or result)
  end
  return true
end

-- ============================================================
-- Empty Word paragraphs
-- ============================================================

-- Pandoc normally drops empty <w:p/> elements when DOCX is converted to
-- Markdown because Markdown blank lines are paragraph separators, not empty
-- paragraphs.  Convert a COPY of the DOCX and temporarily put a unique token
-- inside truly empty Word paragraphs.  Pandoc then preserves their positions.
--
-- The original DOCX is never modified here.
local function make_pandoc_read_copy_with_empty_markers(docx)
  local temp_docx = vim.fn.tempname() .. ".docx"

  local copied, copy_err = copy_file(docx, temp_docx)
  if not copied then
    return nil, tostring(copy_err)
  end

  local path = ps_escape(temp_docx)
  local marker = ps_escape(EMPTY_PARAGRAPH_MARKER)
  local tab_marker = ps_escape(INLINE_TAB_MARKER)
  local page_break_marker = ps_escape(pagebreaks.read_marker_prefix())

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$path = '%s'
$marker = '%s'
$tabMarker = '%s'
$pageBreakMarker = '%s'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Update')
    $entry = $zip.GetEntry('word/document.xml')
    if ($null -eq $entry) { throw 'word/document.xml not found' }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    $xmlText = $reader.ReadToEnd()
    $reader.Close()

    [xml]$xml = $xmlText
    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    # Rehydrate metadata only in the disposable Pandoc input copy.  The saved
    # DOCX keeps it in a standard custom property, never in visible body text.
    $customEntry=$zip.GetEntry('docProps/custom.xml')
    if($customEntry){
        $mr=New-Object IO.StreamReader($customEntry.Open())
        $models=New-Object Xml.XmlDocument
        $models.LoadXml($mr.ReadToEnd());$mr.Close()
        $customNs=New-Object Xml.XmlNamespaceManager($models.NameTable)
        $customNs.AddNamespace('cp','http://schemas.openxmlformats.org/officeDocument/2006/custom-properties')
        $customNs.AddNamespace('vt','http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes')
        $stored=$models.SelectSingleNode('/cp:Properties/cp:property[@name="WordVimTables"]/vt:lpwstr',$customNs)
        if($stored){
          $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($stored.InnerText))
          $records=@($json|ConvertFrom-Json)
          $tables=@($xml.SelectNodes('//w:tbl',$ns))
          foreach($record in $records){
            $index=[int]$record.index
            # Metadata may outlive a table deleted or reordered by another
            # editor.  Never make the whole DOCX unreadable for a stale index.
            # If there is exactly one model and one table, their pairing is
            # unambiguous even when an older version stored a wrong index.
            if($index -lt 0 -or $index -ge $tables.Count){
              if($records.Count -eq 1 -and $tables.Count -eq 1){$index=0}else{continue}
            }
            $hex=[string]$record.hex
            if($hex -notmatch '^[0-9A-Fa-f]+$'){continue}
            $p=$xml.CreateElement('w','p',$nsUri)
            $r=$xml.CreateElement('w','r',$nsUri)
            $t=$xml.CreateElement('w','t',$nsUri)
            $t.InnerText='WORDVIM_TABLE_META_'+$hex
            [void]$r.AppendChild($t);[void]$p.AppendChild($r)
            [void]$tables[$index].ParentNode.InsertBefore($p,$tables[$index])
          }
        }
    }

    $paragraphs = @($xml.SelectNodes('//w:body//w:p', $ns))
    $pageBreakIndex = 0

    # Preserve the exact position of every real manual page break in the
    # disposable read copy. Pandoc normally drops a paragraph that contains
    # only <w:br w:type="page"/>. The marker is removed from the Neovim buffer
    # after all row-rewriting import passes and never touches the original.
    foreach ($p in $paragraphs) {
        $pageBreaks = @($p.SelectNodes('.//w:br[@w:type="page"]', $ns))
        if ($pageBreaks.Count -eq 0) { continue }

        $pageBreakIndex++
        $markerText = $pageBreakMarker + [string]$pageBreakIndex

        $visibleParts = @()
        foreach ($t in $p.SelectNodes('.//w:t', $ns)) {
            $visibleParts += [string]$t.InnerText
        }
        $visibleText = ($visibleParts -join '')

        foreach ($br in $pageBreaks) {
            if ($null -ne $br.ParentNode) {
                [void]$br.ParentNode.RemoveChild($br)
            }
        }

        $markerParagraph = $p
        if (-not [string]::IsNullOrWhiteSpace($visibleText)) {
            $markerParagraph = $xml.CreateElement('w', 'p', $nsUri)
            [void]$p.ParentNode.InsertBefore($markerParagraph, $p)
        }

        $markerRun = $xml.CreateElement('w', 'r', $nsUri)
        $markerNode = $xml.CreateElement('w', 't', $nsUri)
        $markerNode.InnerText = $markerText
        [void]$markerRun.AppendChild($markerNode)
        [void]$markerParagraph.AppendChild($markerRun)
    }

    # Include any marker paragraphs inserted above in the sanitisation pass.
    $paragraphs = @($xml.SelectNodes('//w:body//w:p', $ns))

    foreach ($p in $paragraphs) {
        # ------------------------------------------------------------
        # Word Vim read-copy sanitisation (v6.12)
        # ------------------------------------------------------------
        # Pandoc tries to interpret Word SEQ/REF/PAGEREF fields and our
        # internal bookmarks as Markdown links/anchors.  Across repeated
        # save/open cycles that representation is not stable and can leak
        # strings such as []{#_WordVim_Figure_...} or verbose Hyperlink
        # spans into the editor.
        #
        # The ORIGINAL DOCX is never touched here.  On this temporary read
        # copy only, flatten Word Vim fields to their already cached visible
        # result text before Pandoc sees them.  crossrefs.restore_from_docx()
        # later reads the authoritative SEQ/REF/PAGEREF/bookmark metadata
        # directly from the untouched original document.xml.

        $instrParts = @()
        foreach ($instr in $p.SelectNodes('.//w:instrText', $ns)) {
            $instrParts += [string]$instr.InnerText
        }
        $allInstr = ($instrParts -join ' ')

        $isWordVimCaption = $allInstr -match 'SEQ\s+(Figure|Table)'
        $hasWordVimRef = $allInstr -match '(REF|PAGEREF)\s+_WordVim_(Figure|Table)_'

        if ($isWordVimCaption) {
            # Keep the visible label / field result / title runs, but remove
            # field machinery and internal bookmark anchors from the read
            # copy.  Also neutralise Caption style in the read copy so Pandoc
            # does not synthesize an HTML <figure>/<figcaption> block.
            $removeRuns = @($p.SelectNodes('.//w:r[w:fldChar or w:instrText]', $ns))
            foreach ($r in $removeRuns) {
                if ($null -ne $r.ParentNode) { [void]$r.ParentNode.RemoveChild($r) }
            }

            $bookmarkNodes = @($p.SelectNodes('.//w:bookmarkStart | .//w:bookmarkEnd', $ns))
            foreach ($bm in $bookmarkNodes) {
                if ($null -ne $bm.ParentNode) { [void]$bm.ParentNode.RemoveChild($bm) }
            }

            $pPr = $p.SelectSingleNode('w:pPr', $ns)
            if ($null -ne $pPr) {
                $pStyle = $pPr.SelectSingleNode('w:pStyle', $ns)
                if ($null -ne $pStyle) {
                    [void]$pPr.RemoveChild($pStyle)
                }
            }
        }
        elseif ($hasWordVimRef) {
            # For REF/PAGEREF paragraphs keep the cached visible field result
            # text and all ordinary surrounding runs, but remove begin /
            # instruction / separate / end runs.  Without the field codes
            # Pandoc has nothing to turn into internal Markdown hyperlinks.
            $removeRuns = @($p.SelectNodes('.//w:r[w:fldChar or w:instrText]', $ns))
            foreach ($r in $removeRuns) {
                if ($null -ne $r.ParentNode) { [void]$r.ParentNode.RemoveChild($r) }
            }

            # Word Vim bookmarks are implementation details.  REF paragraphs
            # should not normally contain them, but remove any stale ones from
            # old round-trips in the temporary copy as a repair path.
            $bookmarkNodes = @($p.SelectNodes('.//w:bookmarkStart[starts-with(@w:name, "_WordVim_")] | .//w:bookmarkEnd', $ns))
            foreach ($bm in $bookmarkNodes) {
                if ($null -ne $bm.ParentNode) { [void]$bm.ParentNode.RemoveChild($bm) }
            }
        }
        else {
            # Old Word Vim builds could leave an internal bookmark anchor in a
            # paragraph that no longer contains a SEQ field.  Hide only the
            # implementation bookmark on the Pandoc read copy; keep its text.
            $wordVimStarts = @($p.SelectNodes('.//w:bookmarkStart[starts-with(@w:name, "_WordVim_")]', $ns))
            foreach ($bmStart in $wordVimStarts) {
                $id = $bmStart.GetAttribute('id', $nsUri)
                if ($null -ne $bmStart.ParentNode) { [void]$bmStart.ParentNode.RemoveChild($bmStart) }
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    $ends = @($p.SelectNodes('.//w:bookmarkEnd[@w:id="' + $id + '"]', $ns))
                    foreach ($bmEnd in $ends) {
                        if ($null -ne $bmEnd.ParentNode) { [void]$bmEnd.ParentNode.RemoveChild($bmEnd) }
                    }
                }
            }
        }

        # Make real Word tabs visible to Pandoc on the temporary read copy.
        # Pandoc otherwise tends to flatten/drop inline <w:tab/> elements.
        # Leading tabs are later migrated back to hidden paragraph metadata,
        # while tabs between words remain literal editor TAB characters.
        $tabNodes = @($p.SelectNodes('.//w:tab', $ns))
        foreach ($tabNode in $tabNodes) {
            $t = $xml.CreateElement('w', 't', $nsUri)
            $t.InnerText = $tabMarker
            [void]$tabNode.ParentNode.ReplaceChild($t, $tabNode)
        }

        # A paragraph is considered truly empty only when it contains no
        # visible text and no structural inline object/field/break/tab.
        # Paragraph properties (w:pPr) are intentionally allowed.
        $meaningful = $p.SelectSingleNode(
          './/w:t | .//w:tab | .//w:br | .//w:cr | .//w:drawing | .//w:object | .//w:pict | .//w:fldChar | .//w:instrText | .//w:sym | .//w:footnoteReference | .//w:endnoteReference',
          $ns
        )

        if ($null -eq $meaningful) {
            $r = $xml.CreateElement('w', 'r', $nsUri)
            $t = $xml.CreateElement('w', 't', $nsUri)
            $t.InnerText = $marker
            [void]$r.AppendChild($t)
            [void]$p.AppendChild($r)
        }
    }

    $entry.Delete()
    $newEntry = $zip.CreateEntry('word/document.xml')
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $xml.Save($writer)
    $writer.Close()
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
]], path, marker, tab_marker, page_break_marker)

  local ok, output = run_powershell(script)
  if not ok then
    vim.fn.delete(temp_docx)
    return nil, output
  end

  return temp_docx
end

-- Remove the temporary marker text from the generated DOCX while keeping the
-- paragraph itself (and its pPr/style/spacing).  Thus the saved file contains
-- a genuine empty Word paragraph, not marker text.
local function remove_empty_paragraph_markers(docx)
  local path = ps_escape(docx)
  local marker = ps_escape(EMPTY_PARAGRAPH_MARKER)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$path = '%s'
$marker = '%s'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Update')
    $entry = $zip.GetEntry('word/document.xml')
    if ($null -eq $entry) { throw 'word/document.xml not found' }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    $xmlText = $reader.ReadToEnd()
    $reader.Close()

    [xml]$xml = $xmlText
    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $nodes = @($xml.SelectNodes('//w:t[text()="' + $marker + '"]', $ns))
    foreach ($t in $nodes) {
        $run = $t.ParentNode
        if ($null -ne $run -and $run.LocalName -eq 'r') {
            [void]$run.ParentNode.RemoveChild($run)
        }
        else {
            $t.InnerText = ''
        }
    }

    $entry.Delete()
    $newEntry = $zip.CreateEntry('word/document.xml')
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $xml.Save($writer)
    $writer.Close()
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
]], path, marker)

  local ok, output = run_powershell(script)
  if not ok then
    vim.notify(
      "Word Vim: could not restore empty Word paragraphs:\n" .. output,
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

local function create_backup(original)
  local backup = original .. ".bak"

  if vim.fn.filereadable(backup) == 1 then
    return true
  end

  local ok, err = copy_file(original, backup)
  if not ok then
    vim.notify(
      "Word Vim: could not create backup:\n" .. tostring(err),
      vim.log.levels.ERROR
    )
    return false
  end

  vim.notify("Word Vim backup created:\n" .. backup, vim.log.levels.INFO)
  return true
end

local function apply_docx_window_profile(buf, win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  if not window_restore[win] then
    window_restore[win] = {
      wrap = vim.wo[win].wrap,
      linebreak = vim.wo[win].linebreak,
      number = vim.wo[win].number,
      relativenumber = vim.wo[win].relativenumber,
      signcolumn = vim.wo[win].signcolumn,
      statusline = vim.wo[win].statusline,
    }
  end

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = true
  vim.wo[win].relativenumber = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].statusline =
    "%t %m %= %{v:lua.WordVimLanguageStatus()}  %{v:lua.WordVimPageStatus()} %l:%c %p%%"
end

local function restore_window_profile(win)
  local saved = window_restore[win]
  if not saved or not vim.api.nvim_win_is_valid(win) then
    window_restore[win] = nil
    return
  end

  vim.wo[win].wrap = saved.wrap
  vim.wo[win].linebreak = saved.linebreak
  vim.wo[win].number = saved.number
  vim.wo[win].relativenumber = saved.relativenumber
  vim.wo[win].signcolumn = saved.signcolumn
  vim.wo[win].statusline = saved.statusline
  window_restore[win] = nil
end

local function apply_docx_buffer_profile(buf)
  vim.b[buf].wordvim_docx = true
  vim.bo[buf].smartindent = false
  vim.bo[buf].undofile = false
  vim.bo[buf].formatoptions = ""

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    apply_docx_window_profile(buf, win)
  end
end

-- ============================================================
-- Read styles.xml from a temporary DOCX copy
-- ============================================================

local function read_word_styles_from_copy(docx)
  local temp_docx = vim.fn.tempname() .. ".docx"

  local copied, copy_err = copy_file(docx, temp_docx)
  if not copied then
    vim.notify(
      "Word Vim: could not create temporary DOCX copy:\n" .. tostring(copy_err),
      vim.log.levels.WARN
    )
    return {}
  end

  local path = ps_escape(temp_docx)

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem

$path = '%s'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)

    $entry = $zip.GetEntry('word/styles.xml')
    if ($null -eq $entry) {
        throw 'word/styles.xml not found'
    }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
    $reader.Close()

    $nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $all = $xml.SelectNodes('//w:styles/w:style', $ns)

    foreach ($style in $all) {
        $type = $style.GetAttribute('type', $nsUri)
        $id = $style.GetAttribute('styleId', $nsUri)

        $nameNode = $style.SelectSingleNode('w:name', $ns)
        if ($null -eq $nameNode) {
            continue
        }

        $name = $nameNode.GetAttribute('val', $nsUri)

        $basedOn = ''
        $based = $style.SelectSingleNode('w:basedOn', $ns)

        if ($null -ne $based) {
            $basedId = $based.GetAttribute('val', $nsUri)

            foreach ($candidate in $all) {
                if ($candidate.GetAttribute('styleId', $nsUri) -eq $basedId) {
                    $candidateName = $candidate.SelectSingleNode('w:name', $ns)

                    if ($null -ne $candidateName) {
                        $basedOn = $candidateName.GetAttribute('val', $nsUri)
                    }

                    break
                }
            }
        }

        $font = ''
        $fonts = $style.SelectSingleNode('w:rPr/w:rFonts', $ns)
        if ($null -ne $fonts) {
            $font = $fonts.GetAttribute('ascii', $nsUri)
        }

        $size = ''
        $sz = $style.SelectSingleNode('w:rPr/w:sz', $ns)
        if ($null -ne $sz) {
            $half = $sz.GetAttribute('val', $nsUri)
            if (-not [string]::IsNullOrWhiteSpace($half)) {
                $size = ([double]$half / 2)
            }
        }

        $bold = 'no'
        if ($null -ne $style.SelectSingleNode('w:rPr/w:b', $ns)) {
            $bold = 'yes'
        }

        $italic = 'no'
        if ($null -ne $style.SelectSingleNode('w:rPr/w:i', $ns)) {
            $italic = 'yes'
        }

        $underline = 'no'
        if ($null -ne $style.SelectSingleNode('w:rPr/w:u', $ns)) {
            $underline = 'yes'
        }

        $color = ''
        $colorNode = $style.SelectSingleNode('w:rPr/w:color', $ns)
        if ($null -ne $colorNode) {
            $color = $colorNode.GetAttribute('val', $nsUri)
        }

        $alignment = ''
        $jc = $style.SelectSingleNode('w:pPr/w:jc', $ns)
        if ($null -ne $jc) {
            $alignment = $jc.GetAttribute('val', $nsUri)
        }

        $before = ''
        $after = ''
        $spacing = $style.SelectSingleNode('w:pPr/w:spacing', $ns)

        if ($null -ne $spacing) {
            $b = $spacing.GetAttribute('before', $nsUri)
            $a = $spacing.GetAttribute('after', $nsUri)

            if (-not [string]::IsNullOrWhiteSpace($b)) {
                $before = ([double]$b / 20)
            }

            if (-not [string]::IsNullOrWhiteSpace($a)) {
                $after = ([double]$a / 20)
            }
        }

        Write-Output(
          $type      + "`t" +
          $id        + "`t" +
          $name      + "`t" +
          $basedOn   + "`t" +
          $font      + "`t" +
          $size      + "`t" +
          $bold      + "`t" +
          $italic    + "`t" +
          $underline + "`t" +
          $color     + "`t" +
          $alignment + "`t" +
          $before    + "`t" +
          $after
        )
    }
}
finally {
    if ($null -ne $zip) {
        $zip.Dispose()
    }
}
]], path)

  local ok, output = run_powershell(script)
  vim.fn.delete(temp_docx)

  if not ok then
    vim.notify(
      "Word Vim: could not read Word styles:\n" .. output,
      vim.log.levels.WARN
    )
    return {}
  end

  local result = {}

  for line in output:gmatch("[^\r\n]+") do
    local fields = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do
      table.insert(fields, field)
    end

    if fields[1] and fields[2] and fields[3] then
      table.insert(result, {
        type = fields[1],
        id = fields[2],
        name = fields[3],
        based_on = fields[4] or "",
        font = fields[5] or "",
        size = fields[6] or "",
        bold = fields[7] or "no",
        italic = fields[8] or "no",
        underline = fields[9] or "no",
        color = fields[10] or "",
        alignment = fields[11] or "",
        before = fields[12] or "",
        after = fields[13] or "",
      })
    end
  end

  return result
end

-- ============================================================
-- Inline underline editor markers
--
-- Editor representation:     ++underlined text++
-- Pandoc/Word representation: [underlined text]{custom-style="Underline"}
-- ============================================================

local function underline_to_editor_lines(lines)
  local result = {}

  for _, line in ipairs(lines or {}) do
    line = tostring(line or "")
    line = line:gsub(
      "%[([^%]]-)%]%{custom%-style=[\"']Underline[\"']%}",
      "++%1++"
    )
    table.insert(result, line)
  end

  return result
end

local function underline_to_markdown_lines(lines)
  local result = {}

  for _, line in ipairs(lines or {}) do
    line = tostring(line or "")
    line = line:gsub(
      "%+%+([^\n]-)%+%+",
      "[%1]{custom-style=\"Underline\"}"
    )
    table.insert(result, line)
  end

  return result
end

-- ============================================================
-- Remove visible paragraph custom-style wrappers
-- ============================================================

local function clean_style_blocks(lines)
  local clean = {}
  local assignments = {}
  local i = 1

  local function is_div_close(line)
    return line:match("^%s*:::%s*$") ~= nil
      or line:match("^%s*\\:::%s*$") ~= nil
  end

  local function list_prefix_and_body(line)
    local prefix, body = line:match("^(%s*[-+*]%s+)(.*)$")
    if prefix then
      return prefix, body
    end

    return line:match("^(%s*%d+[%.%)]%s+)(.*)$")
  end

  local function inline_list_style(line)
    -- Pandoc often collapses a fenced paragraph style INSIDE a list item
    -- to a single line during DOCX -> Markdown round-trip:
    --
    --   1.  ::: {custom-style="Normal"} text :::
    --
    -- Older Word Vim versions did not unwrap this form.  On the next save
    -- Pandoc could escape the leftover fences, exposing visible "\\:::"
    -- tokens in the editor.
    local normalized = tostring(line or ""):gsub("\\:::", ":::")
    local prefix, body = list_prefix_and_body(normalized)

    if not prefix then
      return nil
    end

    local style_name, content = body:match(
      '^:::%s*{custom%-style="([^"]+)"}%s*(.-)%s*:::%s*$'
    )

    if not style_name then
      return nil
    end

    return prefix, style_name, content
  end

  local function multiline_list_style(line)
    -- Three-line variant emitted by some Pandoc versions:
    --
    -- -   ::: {custom-style="Normal"}
    --     text
    --     :::
    local normalized = tostring(line or ""):gsub("\\:::", ":::")
    local prefix, body = list_prefix_and_body(normalized)

    if not prefix then
      return nil
    end

    local style_name = body:match(
      '^:::%s*{custom%-style="([^"]+)"}%s*$'
    )

    if style_name then
      return prefix, style_name
    end

    return nil
  end

  local function strip_legacy_list_fences(line)
    -- Migration for documents already saved by the buggy implementation.
    -- They can contain trailing escaped closing fences such as:
    --
    --   1 remark text \\::: \\:::
    --
    -- Only list items are touched, and only trailing fence tokens.
    local prefix, body = list_prefix_and_body(line)
    if not prefix then
      return line
    end

    local changed = false
    while body:match("%s+\\:::%s*$") do
      body = body:gsub("%s+\\:::%s*$", "")
      changed = true
    end

    if changed then
      return prefix .. body
    end

    return line
  end

  while i <= #lines do
    -- --------------------------------------------------------
    -- Case 1: styled list paragraph collapsed to one line.
    -- --------------------------------------------------------
    local inline_prefix, inline_style, inline_content = inline_list_style(lines[i])

    if inline_prefix then
      table.insert(clean, inline_prefix .. inline_content)
      table.insert(assignments, {
        row = #clean - 1,
        style = inline_style,
      })
      i = i + 1
    else
      -- ------------------------------------------------------
      -- Case 2: three-line custom-style block nested in a list item.
      -- ------------------------------------------------------
      local list_prefix, list_style = multiline_list_style(lines[i])

      if list_prefix then
        i = i + 1
        local first = true
        local first_content_row = nil

        while i <= #lines and not is_div_close(lines[i]) do
          local content = lines[i]

          if first then
            content = content:gsub("^%s*", "")
            table.insert(clean, list_prefix .. content)
            first_content_row = #clean - 1
            first = false
          else
            table.insert(clean, content)
          end

          i = i + 1
        end

        if first_content_row then
          table.insert(assignments, {
            row = first_content_row,
            style = list_style,
          })
        end

        if i <= #lines and is_div_close(lines[i]) then
          i = i + 1
        end
      else
        -- ----------------------------------------------------
        -- Case 3: ordinary top-level paragraph style fenced Div.
        -- ----------------------------------------------------
        local normalized = tostring(lines[i] or ""):gsub("\\:::", ":::")
        local style_name = normalized:match(
          '^%s*:::%s*{custom%-style="([^"]+)"}%s*$'
        )

        if style_name then
          i = i + 1
          local first_content_row = nil

          while i <= #lines and not is_div_close(lines[i]) do
            table.insert(clean, lines[i])

            if not first_content_row and lines[i]:match("%S") then
              first_content_row = #clean - 1
            end

            i = i + 1
          end

          if first_content_row then
            table.insert(assignments, {
              row = first_content_row,
              style = style_name,
            })
          end

          if i <= #lines and is_div_close(lines[i]) then
            i = i + 1
          end
        else
          table.insert(clean, strip_legacy_list_fences(lines[i]))
          i = i + 1
        end
      end
    end
  end

  return clean, assignments
end

local function strip_leaked_style_fences(lines)
  local out = {}
  for _, raw in ipairs(lines or {}) do
    local line = tostring(raw or "")
    -- Migration cleanup for documents already affected by older releases.
    -- Only trailing/standalone fence artifacts are removed.
    line = line:gsub("%s+\\:::%s*$", "")
    line = line:gsub("%s+:::%s*$", "")
    if not line:match("^%s*\\?:::%s*$") then
      table.insert(out, line)
    end
  end
  return out
end

-- ============================================================
-- Normalize Pandoc HTML <figure> blocks back to Word Vim rows
-- ============================================================
--
-- When an image paragraph is followed by a real Word Caption, Pandoc may
-- serialize the pair as raw HTML instead of ordinary Markdown, for example:
--
--   <figure data-custom-style="Body Text">
--   <img src=".../media/rId295.png" style="width:3.14961in;height:6.28831in" />
--   <figcaption><div data-custom-style="Caption">
--   <p>Figure 1 - test</p>
--   </div></figcaption>
--   </figure>
--
-- Word Vim must never expose that conversion artifact to the editor.  Collapse
-- it back to exactly two logical rows: a Markdown image and the visible caption
-- text. crossrefs.restore_from_docx() then reattaches the authoritative SEQ /
-- bookmark metadata from word/document.xml, just as it does for captions that
-- were created manually.
local function normalize_pandoc_figures(lines)
  local result = {}
  local i = 1

  local function html_decode(value)
    value = tostring(value or "")

    value = value:gsub("&#[xX]([0-9a-fA-F]+);", function(hex)
      local n = tonumber(hex, 16)
      if not n then
        return ""
      end
      local ok, ch = pcall(vim.fn.nr2char, n)
      return ok and ch or ""
    end)

    value = value:gsub("&#(%d+);", function(dec)
      local n = tonumber(dec, 10)
      if not n then
        return ""
      end
      local ok, ch = pcall(vim.fn.nr2char, n)
      return ok and ch or ""
    end)

    -- Decode ampersand last so an entity such as &amp;lt; does not get
    -- decoded twice in a single pass.
    value = value:gsub("&quot;", '"')
    value = value:gsub("&apos;", "'")
    value = value:gsub("&#39;", "'")
    value = value:gsub("&lt;", "<")
    value = value:gsub("&gt;", ">")
    value = value:gsub("&nbsp;", " ")
    value = value:gsub("&amp;", "&")

    return value
  end

  local function attr_value(tag, name)
    local double = tag:match(name .. '%s*=%s*"([^"]*)"')
    if double ~= nil then
      return html_decode(double)
    end

    local single = tag:match(name .. "%s*=%s*'([^']*)'")
    if single ~= nil then
      return html_decode(single)
    end

    return nil
  end

  local function pretty_width(width)
    width = vim.trim(tostring(width or ""))
    if width == "" then
      return ""
    end

    local inches = width:match("^([%d%.]+)in$")
    if inches then
      local value = tonumber(inches)
      if value then
        local cm = value * 2.54
        local rounded = math.floor(cm * 100 + 0.5) / 100

        -- Pandoc/Word commonly writes values such as 3.14961in for an
        -- original 8cm width.  Show the friendly metric form again when
        -- conversion lands cleanly on hundredths of a centimetre.
        if math.abs(cm - rounded) < 0.001 then
          local text = string.format("%.2f", rounded)
          text = text:gsub("0+$", ""):gsub("%.$", "")
          return text .. "cm"
        end
      end
    end

    return width
  end

  local function caption_text(fragment)
    fragment = tostring(fragment or "")
    fragment = fragment:gsub("<[bB][rR]%s*/?>", " ")
    fragment = fragment:gsub("<[^>]->", " ")
    fragment = html_decode(fragment)
    fragment = fragment:gsub("%s+", " ")
    return vim.trim(fragment)
  end

  while i <= #lines do
    if tostring(lines[i]):match("^%s*<figure[%s>]?") then
      local block = { lines[i] }
      local j = i + 1
      local closed = tostring(lines[i]):find("</figure>", 1, true) ~= nil

      while j <= #lines and not closed do
        table.insert(block, lines[j])
        if tostring(lines[j]):find("</figure>", 1, true) then
          closed = true
        end
        j = j + 1
      end

      if closed then
        local html = table.concat(block, "\n")
        local img_tag = html:match("<img%s+.-%s*/?>")
          or html:match("<img%s+.-%s*>")

        local src = img_tag and attr_value(img_tag, "src") or nil

        if src and src ~= "" then
          -- Forward slashes are safer inside Markdown destinations on Windows;
          -- Pandoc accepts them and can still read the extracted temporary file.
          src = src:gsub("\\", "/")

          local width = ""
          local style = attr_value(img_tag, "style") or ""
          width = style:match("[Ww][Ii][Dd][Tt][Hh]%s*:%s*([^;]+)") or ""

          if width == "" then
            width = attr_value(img_tag, "width") or ""
          end

          width = pretty_width(width)

          local image_line = "![](<" .. src .. ">)"
          if width ~= "" then
            image_line = image_line .. "{width=" .. width .. "}"
          end

          local figure_tag = html:match("<figure[^>]*>") or ""
          local figure_style = attr_value(figure_tag, "data%-custom%-style") or ""

          -- Re-create a temporary fenced custom-style wrapper so the existing
          -- clean_style_blocks() path can preserve the Word paragraph style as
          -- a hidden extmark without showing any HTML to the user.
          if figure_style ~= "" and figure_style:lower() ~= "normal" then
            table.insert(result, '::: {custom-style="' .. figure_style .. '"}')
            table.insert(result, image_line)
            table.insert(result, ":::")
          else
            table.insert(result, image_line)
          end

          local figcaption = html:match("<figcaption[^>]*>(.-)</figcaption>")
          local text = caption_text(figcaption)
          if text ~= "" then
            local caption_div = figcaption and figcaption:match("<div[^>]*>") or ""
            local caption_style = attr_value(caption_div, "data%-custom%-style") or ""

            if caption_style ~= "" and caption_style:lower() ~= "normal" then
              table.insert(result, '::: {custom-style="' .. caption_style .. '"}')
              table.insert(result, text)
              table.insert(result, ":::")
            else
              table.insert(result, text)
            end
          end

          i = j
        else
          -- Unknown/foreign figure shape: leave it untouched rather than
          -- destroying content we cannot confidently reconstruct.
          for _, line in ipairs(block) do
            table.insert(result, line)
          end
          i = j
        end
      else
        table.insert(result, lines[i])
        i = i + 1
      end
    else
      table.insert(result, lines[i])
      i = i + 1
    end
  end

  return result
end


-- ============================================================
-- Normalize Pandoc hyperlink syntax for Word REF/PAGEREF fields
-- ============================================================
--
-- A real Word cross-reference created by crossrefs.lua can be emitted by
-- Pandoc as verbose Markdown hyperlinks, for example:
--
--   [Figure 1]{custom-style="Hyperlink"}(#X...), page [[1]{custom-style="Hyperlink"}](#X...)
--
-- The DOCX remains correct; this is only Pandoc's editor representation.  The
-- authoritative bookmark/REF metadata is restored later by
-- crossrefs.restore_from_docx().  Here we only collapse the visible syntax to
-- the compact Word Vim form expected by that restoration pass:
--
--   Figure 1, page 1
--
-- Do this before compact_editor_lines(), while Pandoc's raw inline syntax is
-- still intact.
local function normalize_pandoc_crossrefs(lines)
  local result = vim.deepcopy(lines)

  local function collapse(line, label)
    -- Pandoc commonly emits the first REF result as
    -- [Figure 1]{custom-style="Hyperlink"}(#bookmark)
    -- and PAGEREF as
    -- [[1]{custom-style="Hyperlink"}](#bookmark).
    -- Bookmark ids are deliberately captured and compared when possible so we
    -- do not accidentally collapse unrelated hyperlinks that merely resemble a
    -- cross-reference.
    local escaped = vim.pesc(label)

    local pattern =
      "%[" .. escaped .. "%s+(%d+)%]%{custom%-style=[\"']Hyperlink[\"']%}%((#[^%)]+)%)" ..
      "%s*,%s*page%s*" ..
      "%[%[(%d+)%]%{custom%-style=[\"']Hyperlink[\"']%}%]%((#[^%)]+)%)"

    line = line:gsub(pattern, function(number, ref_target, page, page_target)
      if ref_target == page_target then
        return label .. " " .. number .. ", page " .. page
      end
      return "[" .. label .. " " .. number .. "]{custom-style=\"Hyperlink\"}(" .. ref_target ..
        "), page [[" .. page .. "]{custom-style=\"Hyperlink\"}](" .. page_target .. ")"
    end)

    -- Pandoc can also wrap the styled REF text in an outer Markdown link:
    --   [[Figure 1]{custom-style="Hyperlink"}](#bookmark), page
    --   [[1]{custom-style="Hyperlink"}](#bookmark)
    -- This is the exact representation seen in Word Vim v6.10 after reopening
    -- some DOCX files. Collapse it as well, but only when REF and PAGEREF point
    -- to the same bookmark.
    local wrapped =
      "%[%[" .. escaped .. "%s+(%d+)%]%{custom%-style=[\"']Hyperlink[\"']%}%]%((#[^%)]+)%)" ..
      "%s*,%s*page%s*" ..
      "%[%[(%d+)%]%{custom%-style=[\"']Hyperlink[\"']%}%]%((#[^%)]+)%)"

    line = line:gsub(wrapped, function(number, ref_target, page, page_target)
      if ref_target == page_target then
        return label .. " " .. number .. ", page " .. page
      end
      return "[[" .. label .. " " .. number .. "]{custom-style=\"Hyperlink\"}](" .. ref_target ..
        "), page [[" .. page .. "]{custom-style=\"Hyperlink\"}](" .. page_target .. ")"
    end)

    -- Some Pandoc versions omit the custom-style span while preserving both
    -- internal links. Support that representation too.
    local simple =
      "%[" .. escaped .. "%s+(%d+)%]%((#[^%)]+)%)" ..
      "%s*,%s*page%s*" ..
      "%[(%d+)%]%((#[^%)]+)%)"

    line = line:gsub(simple, function(number, ref_target, page, page_target)
      if ref_target == page_target then
        return label .. " " .. number .. ", page " .. page
      end
      return "[" .. label .. " " .. number .. "](" .. ref_target .. "), page [" .. page .. "](" .. page_target .. ")"
    end)

    return line
  end

  for i, line in ipairs(result) do
    line = collapse(tostring(line), "Figure")
    line = collapse(line, "Table")
    result[i] = line
  end

  return result
end

-- ============================================================
-- Canonicalize ordinary Pandoc image dimensions
-- ============================================================
-- Pandoc/Word may reopen an image originally entered as width=8cm as
-- width="3.149606...in" height="...in".  Word Vim only needs the explicit
-- width for its editor representation; the aspect ratio is preserved by Word.
-- Convert inch widths back to a friendly cm value and drop Pandoc's derived
-- height so repeated save/open cycles stay visually stable.
local function normalize_pandoc_image_dimensions(lines)
  local result = vim.deepcopy(lines)

  local function in_to_cm(text)
    local n = tonumber(text)
    if not n then
      return nil
    end
    local cm = n * 2.54
    local rounded = math.floor(cm * 100 + 0.5) / 100
    local out = string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
    return out .. "cm"
  end

  for i, raw in ipairs(result) do
    local line = tostring(raw or "")
    if line:match("!%[") then
      -- Quoted Pandoc attributes: {width="3.1496in" height="2.34in"}
      line = line:gsub(
        '{%s*width="([%d%.]+)in"%s+height="[%d%.]+in"%s*}',
        function(width)
          local cm = in_to_cm(width)
          return cm and ("{width=" .. cm .. "}") or ("{width=\"" .. width .. "in\"}")
        end
      )

      -- Same form without quotes.
      line = line:gsub(
        '{%s*width=([%d%.]+)in%s+height=[%d%.]+in%s*}',
        function(width)
          local cm = in_to_cm(width)
          return cm and ("{width=" .. cm .. "}") or ("{width=" .. width .. "in}")
        end
      )

      -- Width-only quoted attribute.
      line = line:gsub('width="([%d%.]+)in"', function(width)
        local cm = in_to_cm(width)
        return cm and ("width=" .. cm) or ("width=\"" .. width .. "in\"")
      end)
    end
    result[i] = line
  end

  return result
end

local function compact_editor_lines(lines, assignments)
  local compact = {}
  local old_to_new = {}

  local in_fence = false
  local fence_token = nil

  for old_index, line in ipairs(lines) do
    local old_row = old_index - 1
    local trimmed = vim.trim(line)
    local is_pipe_table_line = trimmed:match("^|.*|$") ~= nil

    local fence = trimmed:match("^(```+)")
      or trimmed:match("^(~~~+)")

    if fence then
      if not in_fence then
        in_fence = true
        fence_token = fence:sub(1, 1)
      elseif fence:sub(1, 1) == fence_token then
        in_fence = false
        fence_token = nil
      end

      old_to_new[old_row] = #compact
      table.insert(compact, line)

    elseif in_fence then
      old_to_new[old_row] = #compact
      table.insert(compact, line)

    elseif is_pipe_table_line and line:find(EMPTY_PARAGRAPH_MARKER, 1, true) then
      -- Empty paragraphs inside Word table cells are emitted by Pandoc on a
      -- pipe-table row rather than on a line of their own. Remove the
      -- temporary read marker from the cell while preserving the row and its
      -- delimiters, so an empty cell reopens as an empty cell.
      local cleaned = line:gsub(EMPTY_PARAGRAPH_MARKER, "")
      old_to_new[old_row] = #compact
      table.insert(compact, cleaned)

    elseif vim.trim(line) == EMPTY_PARAGRAPH_MARKER then
      -- This is a real empty <w:p/> that was temporarily marked in the
      -- DOCX copy before Pandoc read it. Keep one visible empty editor row.
      old_to_new[old_row] = #compact
      table.insert(compact, "")

    elseif line:match("^%s*$") then
      -- Ordinary Markdown blank lines are only paragraph separators.
      -- Unlike the marker above, they do NOT represent empty Word paragraphs.

    else
      old_to_new[old_row] = #compact
      table.insert(compact, line)
    end
  end

  local remapped = {}

  for _, item in ipairs(assignments or {}) do
    local new_row = old_to_new[item.row]

    if new_row ~= nil then
      table.insert(remapped, {
        row = new_row,
        style = item.style,
      })
    end
  end

  return compact, remapped
end

local function build_markdown_for_save(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Pandoc does not preserve literal TAB characters inside ordinary text as
  -- Word tabs. Protect inline TABs with a token and turn that token into
  -- <w:tab/> in indents.apply_to_docx() after Pandoc creates the DOCX.
  for i, line in ipairs(lines) do
    lines[i] = (line or ""):gsub("\t", INLINE_TAB_MARKER)
  end

  -- Convert the compact editor underline marker back to Pandoc's native
  -- custom-style span before DOCX generation.
  lines = underline_to_markdown_lines(lines)

  -- Replace caption/reference display text with safe temporary markers.
  lines = crossrefs.prepare_markdown_lines(buf, lines)

  -- Convert Word Vim list labels/symbols back to valid nested Markdown
  -- before the existing DOCX-save logic processes them.
  lines = lists.to_markdown_lines(lines)

  local style_map = styles.get_style_map(buf)
  local result = {}

  local function is_table_line(line)
    local t = vim.trim(line or "")
    return t:match("^|.*|$") ~= nil
  end

  local function is_list_line(line)
    return (line or ""):match("^%s*[-+*]%s+") ~= nil
      or (line or ""):match("^%s*%d+[%.%)]%s+") ~= nil
  end

  local function is_fence(line)
    local t = vim.trim(line or "")
    return t:match("^```+") ~= nil
      or t:match("^~~~+") ~= nil
  end

  local function hard_break(line)
    return (line or ""):match("%s%s$") ~= nil
  end

  local function ensure_blank()
    if #result > 0 and result[#result] ~= "" then
      table.insert(result, "")
    end
  end

  local function emit_page_break(row)
    if pagebreaks.has_before(buf, row) then
      ensure_blank()
      table.insert(
        result,
        pagebreaks.marker_for_row(row)
      )
      ensure_blank()
    end
  end

  local i = 1
  local in_fence = false

  while i <= #lines do
    local line = lines[i]
    local row = i - 1

    local table_block, table_span = tables.lines_at(buf, row)

    if table_block then
      emit_page_break(row)
      ensure_blank()
      for _, table_line in ipairs(table_block) do table.insert(result, table_line) end
      ensure_blank()
      i = i + (table_span or 1)

    elseif toc.has_anchor(buf, row) then
      emit_page_break(row)
      ensure_blank()
      table.insert(
        result,
        toc.marker_for_row(row)
      )
      ensure_blank()
      i = i + 1

    elseif is_fence(line) then
      emit_page_break(row)
      ensure_blank()
      in_fence = not in_fence
      table.insert(result, line)
      i = i + 1

      while i <= #lines and in_fence do
        local code_line = lines[i]
        table.insert(result, code_line)

        if is_fence(code_line) then
          in_fence = false
        end

        i = i + 1
      end

      ensure_blank()

    elseif is_table_line(line) then
      emit_page_break(row)
      ensure_blank()

      while i <= #lines and is_table_line(lines[i]) do
        table.insert(result, lines[i])
        i = i + 1
      end

      ensure_blank()

    elseif is_list_line(line) then
      ensure_blank()

      while i <= #lines and is_list_line(lines[i]) do
        local list_row = i - 1
        emit_page_break(list_row)
        local list_style = style_map[list_row]

        if
          list_style
          and list_style ~= ""
          and list_style ~= "Normal"
          and list_style ~= "List Paragraph"
          and list_style ~= "Body Text"
        then
          -- Keep genuinely custom paragraph styles inside the list item.
          -- Default body/list styles are deliberately NOT wrapped in a
          -- Pandoc fenced Div.  Pandoc can leak those fences back as visible
          -- \::: tokens after repeated DOCX round-trips.
          local prefix, body = lines[i]:match("^(%s*[-+*]%s+)(.*)$")

          if not prefix then
            prefix, body = lines[i]:match(
              "^(%s*%d+[%.%)]%s+)(.*)$"
            )
          end

          if prefix then
            table.insert(
              result,
              prefix
                .. '::: {custom-style="'
                .. list_style
                .. '"}'
            )
            table.insert(result, "    " .. (body or ""))
            table.insert(result, "    :::")
          else
            table.insert(result, lines[i])
          end
        else
          table.insert(result, lines[i])
        end

        i = i + 1
      end

      ensure_blank()

    else
      emit_page_break(row)
      ensure_blank()

      local style_name = style_map[row]
      local paragraph_lines = { line }

      -- Shift+Enter continuation lines belong to the same Word
      -- paragraph. They are recognized by two trailing spaces.
      while
        i < #lines
        and hard_break(paragraph_lines[#paragraph_lines])
      do
        i = i + 1
        table.insert(paragraph_lines, lines[i])
      end

      local heading_level = style_name
        and tostring(style_name):match("^Heading%s+(%d)$")
      heading_level = tonumber(heading_level)

      local first_heading_hashes = tostring(paragraph_lines[1] or "")
        :match("^(#+)%s+")
      local native_heading = heading_level
        and first_heading_hashes
        and #first_heading_hashes == heading_level

      if native_heading then
        -- Do not trust Pandoc/reference-doc style resolution for headings.
        -- We write a temporary plain-text marker and, after Pandoc creates the
        -- DOCX, replace the marker with a real w:pStyle=HeadingN directly in
        -- document.xml.  This makes Heading 1..9 deterministic even when a
        -- document contains duplicate/custom style definitions.
        local first = paragraph_lines[1]:gsub("^#+%s*", "")
        table.insert(
          result,
          HEADING_MARKER_PREFIX .. tostring(heading_level) .. "_ " .. first
        )
        for idx = 2, #paragraph_lines do
          table.insert(
            result,
            paragraph_lines[idx] == "" and EMPTY_PARAGRAPH_MARKER or paragraph_lines[idx]
          )
        end
      elseif
        style_name
        and style_name ~= ""
      then
        -- Explicit non-heading styles, INCLUDING "Normal", must be written.
        -- Without an explicit Normal custom style, Pandoc can fall back to
        -- the reference document's body paragraph style (commonly Body Text).
        table.insert(
          result,
          '::: {custom-style="' .. style_name .. '"}'
        )

        for _, paragraph_line in ipairs(paragraph_lines) do
          table.insert(
            result,
            paragraph_line == "" and EMPTY_PARAGRAPH_MARKER or paragraph_line
          )
        end

        table.insert(result, ":::")
      else
        for _, paragraph_line in ipairs(paragraph_lines) do
          table.insert(
            result,
            paragraph_line == "" and EMPTY_PARAGRAPH_MARKER or paragraph_line
          )
        end
      end

      ensure_blank()
      i = i + 1
    end
  end

  -- Do not leave excessive trailing blank lines.
  while #result > 0 and result[#result] == "" do
    table.remove(result)
  end

  return result
end

-- ============================================================
-- Write one real Word style into styles.xml
-- ============================================================

local function write_word_style(docx, spec)
  local function b(value)
    return value and "true" or "false"
  end

  local path = ps_escape(docx)
  local name = ps_escape(spec.name)
  local style_id = ps_escape(spec.id)
  local style_type = ps_escape(spec.type or "paragraph")
  local based_on = ps_escape(spec.based_on or "")
  local font = ps_escape(spec.font or "")
  local size = ps_escape(spec.size or "")
  local color = ps_escape((spec.color or ""):gsub("#", ""))
  local alignment = ps_escape(spec.alignment or "")
  local before = ps_escape(spec.before or "")
  local after = ps_escape(spec.after or "")
  local outline_level = ps_escape(spec.outline_level or "")
  local quick_style = spec.quick_style == true

  local script = string.format([[
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$path = '%s'
$name = '%s'
$styleId = '%s'
$type = '%s'
$basedName = '%s'
$font = '%s'
$size = '%s'
$bold = [bool]::Parse('%s')
$italic = [bool]::Parse('%s')
$underline = [bool]::Parse('%s')
$color = '%s'
$alignment = '%s'
$before = '%s'
$after = '%s'
$outlineLevel = '%s'
$quickStyle = [bool]::Parse('%s')

$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) (
    'wordvim_style_' + [Guid]::NewGuid().ToString('N')
)
$rebuilt = $path + '.wordvim-rebuilt'

try {
    [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory(
        $path,
        $tempDir
    )

    $stylesPath = Join-Path $tempDir 'word\styles.xml'

    if (-not (Test-Path -LiteralPath $stylesPath)) {
        throw 'word/styles.xml not found'
    }

    [xml]$xml = [System.IO.File]::ReadAllText($stylesPath)

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    function New-WElement([string]$local) {
        return $xml.CreateElement('w', $local, $nsUri)
    }

    function Ensure-Child($parent, [string]$local) {
        $node = $parent.SelectSingleNode('w:' + $local, $ns)

        if ($null -eq $node) {
            $node = New-WElement $local
            [void]$parent.AppendChild($node)
        }

        return $node
    }

    function Remove-Child($parent, [string]$local) {
        $node = $parent.SelectSingleNode('w:' + $local, $ns)

        if ($null -ne $node) {
            [void]$parent.RemoveChild($node)
        }
    }

    $style = $null

    foreach ($candidate in $xml.SelectNodes('//w:style', $ns)) {
        if ($candidate.GetAttribute('styleId', $nsUri) -eq $styleId) {
            $style = $candidate
            break
        }
    }

    if ($null -eq $style) {
        $style = New-WElement 'style'
        $style.SetAttribute('type', $nsUri, $type)
        $style.SetAttribute('styleId', $nsUri, $styleId)
        [void]$xml.DocumentElement.AppendChild($style)
    }

    $style.SetAttribute('type', $nsUri, $type)

    $nameNode = Ensure-Child $style 'name'
    $nameNode.SetAttribute('val', $nsUri, $name)

    if ([string]::IsNullOrWhiteSpace($basedName)) {
        Remove-Child $style 'basedOn'
    }
    else {
        $basedId = $basedName

        foreach ($candidate in $xml.SelectNodes('//w:style', $ns)) {
            $candidateName = $candidate.SelectSingleNode('w:name', $ns)

            if (
                $null -ne $candidateName -and
                $candidateName.GetAttribute('val', $nsUri) -eq $basedName
            ) {
                $basedId = $candidate.GetAttribute('styleId', $nsUri)
                break
            }
        }

        $based = Ensure-Child $style 'basedOn'
        $based.SetAttribute('val', $nsUri, $basedId)
    }

    $rPr = Ensure-Child $style 'rPr'

    if ([string]::IsNullOrWhiteSpace($font)) {
        Remove-Child $rPr 'rFonts'
    }
    else {
        $fonts = Ensure-Child $rPr 'rFonts'
        $fonts.SetAttribute('ascii', $nsUri, $font)
        $fonts.SetAttribute('hAnsi', $nsUri, $font)
        $fonts.SetAttribute('cs', $nsUri, $font)
    }

    if ([string]::IsNullOrWhiteSpace($size)) {
        Remove-Child $rPr 'sz'
        Remove-Child $rPr 'szCs'
    }
    else {
        $half = [int]([double]$size * 2)

        $sz = Ensure-Child $rPr 'sz'
        $sz.SetAttribute('val', $nsUri, "$half")

        $szCs = Ensure-Child $rPr 'szCs'
        $szCs.SetAttribute('val', $nsUri, "$half")
    }

    if ($bold) {
        [void](Ensure-Child $rPr 'b')
    }
    else {
        Remove-Child $rPr 'b'
    }

    if ($italic) {
        [void](Ensure-Child $rPr 'i')
    }
    else {
        Remove-Child $rPr 'i'
    }

    if ($underline) {
        $u = Ensure-Child $rPr 'u'
        $u.SetAttribute('val', $nsUri, 'single')
    }
    else {
        Remove-Child $rPr 'u'
    }

    if ([string]::IsNullOrWhiteSpace($color)) {
        Remove-Child $rPr 'color'
    }
    else {
        $colorNode = Ensure-Child $rPr 'color'
        $colorNode.SetAttribute('val', $nsUri, $color)
    }

    if ($type -eq 'paragraph') {
        $pPr = Ensure-Child $style 'pPr'

        if ([string]::IsNullOrWhiteSpace($alignment)) {
            Remove-Child $pPr 'jc'
        }
        else {
            $jc = Ensure-Child $pPr 'jc'
            $jc.SetAttribute('val', $nsUri, $alignment)
        }

        $spacing = $pPr.SelectSingleNode('w:spacing', $ns)

        if (
            [string]::IsNullOrWhiteSpace($before) -and
            [string]::IsNullOrWhiteSpace($after)
        ) {
            if ($null -ne $spacing) {
                [void]$pPr.RemoveChild($spacing)
            }
        }
        else {
            if ($null -eq $spacing) {
                $spacing = New-WElement 'spacing'
                [void]$pPr.AppendChild($spacing)
            }

            if ([string]::IsNullOrWhiteSpace($before)) {
                $spacing.RemoveAttribute('before', $nsUri)
            }
            else {
                $beforeTwips = [int]([double]$before * 20)
                $spacing.SetAttribute('before', $nsUri, "$beforeTwips")
            }

            if ([string]::IsNullOrWhiteSpace($after)) {
                $spacing.RemoveAttribute('after', $nsUri)
            }
            else {
                $afterTwips = [int]([double]$after * 20)
                $spacing.SetAttribute('after', $nsUri, "$afterTwips")
            }
        }

        # For Word Vim fallback heading styles, preserve real Word outline
        # semantics so TOC/navigation work like native Word headings.
        # Blank means "leave the document's existing property untouched".
        if (-not [string]::IsNullOrWhiteSpace($outlineLevel)) {
            $outline = Ensure-Child $pPr 'outlineLvl'
            $outline.SetAttribute('val', $nsUri, $outlineLevel)
        }
    }

    if ($quickStyle) {
        [void](Ensure-Child $style 'qFormat')
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $false

    $writer = [System.Xml.XmlWriter]::Create($stylesPath, $settings)

    try {
        $xml.Save($writer)
    }
    finally {
        $writer.Dispose()
    }

    if (Test-Path -LiteralPath $rebuilt) {
        Remove-Item -LiteralPath $rebuilt -Force
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $tempDir,
        $rebuilt,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    # Replace only after a completely new valid ZIP has been built.
    [System.IO.File]::Copy($rebuilt, $path, $true)
}
finally {
    if (Test-Path -LiteralPath $rebuilt) {
        Remove-Item -LiteralPath $rebuilt -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
]],
    path,
    name,
    style_id,
    style_type,
    based_on,
    font,
    size,
    b(spec.bold),
    b(spec.italic),
    b(spec.underline),
    color,
    alignment,
    before,
    after,
    outline_level,
    b(quick_style)
  )

  local ok, output = run_powershell(script)

  if not ok then
    vim.notify(
      "Word Vim: could not update Word style:\n" .. output,
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

local function apply_heading_markers_to_docx(docx)
  local path = ps_escape(docx)
  local marker = ps_escape(HEADING_MARKER_PREFIX)

  -- Update the existing DOCX archive in place.  Do NOT extract and rebuild
  -- the ZIP with CreateFromDirectory: on Windows that can create entry names
  -- such as "word\\document.xml", while the rest of Word Vim (and Word itself)
  -- expects canonical OPC names with forward slashes: "word/document.xml".
  local script = string.format([=[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$path = '%s'
$markerPrefix = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::Open($path, [System.IO.Compression.ZipArchiveMode]::Update)

    $docEntry = $zip.GetEntry('word/document.xml')
    if ($null -eq $docEntry) { throw 'word/document.xml not found' }

    $reader = New-Object System.IO.StreamReader($docEntry.Open(), [System.Text.Encoding]::UTF8, $true)
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)

    $headingIds = @{}
    $stylesEntry = $zip.GetEntry('word/styles.xml')
    if ($null -ne $stylesEntry) {
        $stylesReader = New-Object System.IO.StreamReader($stylesEntry.Open(), [System.Text.Encoding]::UTF8, $true)
        try { [xml]$stylesXml = $stylesReader.ReadToEnd() } finally { $stylesReader.Dispose() }
        $stylesNs = New-Object System.Xml.XmlNamespaceManager($stylesXml.NameTable)
        $stylesNs.AddNamespace('w', $nsUri)
        foreach ($style in @($stylesXml.SelectNodes('//w:styles/w:style', $stylesNs))) {
            $nameNode = $style.SelectSingleNode('w:name', $stylesNs)
            if ($null -eq $nameNode) { continue }
            $name = [string]$nameNode.GetAttribute('val', $nsUri)
            if ($name -match '^Heading\s+([1-9])$') {
                $key = [int]$Matches[1]
                if (-not $headingIds.ContainsKey($key)) {
                    $headingIds[$key] = [string]$style.GetAttribute('styleId', $nsUri)
                }
            }
        }
    }

    foreach ($p in $xml.SelectNodes('//w:body//w:p', $ns)) {
        $textNodes = @($p.SelectNodes('.//w:t', $ns))
        if ($textNodes.Count -eq 0) { continue }
        $full = ($textNodes | ForEach-Object { $_.'#text' }) -join ''
        $escaped = [regex]::Escape($markerPrefix)
        $m = [regex]::Match($full, '^' + $escaped + '([1-9])_\s*')
        if (-not $m.Success) { continue }

        $level = [int]$m.Groups[1].Value
        $remaining = $m.Length
        foreach ($t in $textNodes) {
            if ($remaining -le 0) { break }
            $value = [string]$t.'#text'
            if ($value.Length -le $remaining) {
                $remaining -= $value.Length
                $t.'#text' = ''
            } else {
                $t.'#text' = $value.Substring($remaining)
                $remaining = 0
            }
        }

        $pPr = $p.SelectSingleNode('w:pPr', $ns)
        if ($null -eq $pPr) {
            $pPr = $xml.CreateElement('w', 'pPr', $nsUri)
            [void]$p.PrependChild($pPr)
        }
        $pStyle = $pPr.SelectSingleNode('w:pStyle', $ns)
        if ($null -eq $pStyle) {
            $pStyle = $xml.CreateElement('w', 'pStyle', $nsUri)
            [void]$pPr.PrependChild($pStyle)
        }
        $styleId = if ($headingIds.ContainsKey($level) -and -not [string]::IsNullOrWhiteSpace($headingIds[$level])) { $headingIds[$level] } else { 'Heading' + $level }
        $pStyle.SetAttribute('val', $nsUri, $styleId)
    }

    $docEntry.Delete()
    $newEntry = $zip.CreateEntry('word/document.xml', [System.IO.Compression.CompressionLevel]::Optimal)
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    try { $xml.Save($writer) } finally { $writer.Dispose() }
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
]=], path, marker)

  local ok, output = run_powershell(script)
  if not ok then
    vim.notify("Word Vim: could not apply Heading styles:\n" .. output, vim.log.levels.ERROR)
    return false
  end
  return true
end

local function dedupe_word_styles(docx)
  local path = ps_escape(docx)

  -- As above, update styles.xml in the existing OPC archive instead of
  -- rebuilding the DOCX ZIP.  This preserves canonical forward-slash entry
  -- names and avoids breaking later post-processors such as pagebreaks.lua.
  local script = string.format([=[
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$path = '%s'
$nsUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$zip = $null

try {
    $zip = [System.IO.Compression.ZipFile]::Open($path, [System.IO.Compression.ZipArchiveMode]::Update)
    $stylesEntry = $zip.GetEntry('word/styles.xml')
    if ($null -eq $stylesEntry) { exit 0 }

    $reader = New-Object System.IO.StreamReader($stylesEntry.Open(), [System.Text.Encoding]::UTF8, $true)
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w', $nsUri)
    $seenId = @{}
    $seenName = @{}
    $remove = New-Object System.Collections.Generic.List[System.Xml.XmlNode]

    foreach ($style in @($xml.SelectNodes('//w:styles/w:style', $ns))) {
        $id = [string]$style.GetAttribute('styleId', $nsUri)
        $nameNode = $style.SelectSingleNode('w:name', $ns)
        $name = if ($null -ne $nameNode) { [string]$nameNode.GetAttribute('val', $nsUri) } else { '' }
        $idKey = $id.ToLowerInvariant()
        $type = [string]$style.GetAttribute('type', $nsUri)
        $nameKey = ($type.ToLowerInvariant() + '|' + (($name.Trim() -replace '\s+', ' ').ToLowerInvariant()))
        $duplicate = ($idKey -ne '' -and $seenId.ContainsKey($idKey)) -or ($nameKey -ne '' -and $seenName.ContainsKey($nameKey))
        if ($duplicate) { [void]$remove.Add($style); continue }
        if ($idKey -ne '') { $seenId[$idKey] = $true }
        if ($nameKey -ne '') { $seenName[$nameKey] = $true }
    }

    foreach ($style in $remove) { [void]$style.ParentNode.RemoveChild($style) }

    $stylesEntry.Delete()
    $newEntry = $zip.CreateEntry('word/styles.xml', [System.IO.Compression.CompressionLevel]::Optimal)
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    try { $xml.Save($writer) } finally { $writer.Dispose() }
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
]=], path)

  local ok, output = run_powershell(script)
  if not ok then
    vim.notify("Word Vim: could not deduplicate Word styles:\n" .. output, vim.log.levels.ERROR)
    return false
  end
  return true
end

local function apply_style_changes(buf, reference_docx)
  for _, spec in pairs(styles.get_style_changes(buf)) do
    if not write_word_style(reference_docx, spec) then
      return false
    end
  end

  return true
end

-- ============================================================
-- Open DOCX
-- ============================================================

local function open_docx(args)
  local buf = args.buf
  local docx = vim.api.nvim_buf_get_name(buf)

  if docx == "" then
    return
  end

  styles.reset_buffer(buf)

  -- Read styles from a COPY, never by reopening the live DOCX.
  local cached_styles = read_word_styles_from_copy(docx)
  styles.set_cached_styles(buf, cached_styles)
  styles.ensure_underline_style(buf)

  local temp_md = vim.fn.tempname() .. ".md"

  -- Extract embedded DOCX images to a temporary directory.
  -- The directory remains available while this buffer is open,
  -- so Pandoc can read the images again when :w is executed.
  local media_dir = vim.fn.tempname() .. "_wordvim_media"
  vim.fn.mkdir(media_dir, "p")
  vim.b[buf].wordvim_media_dir = media_dir

  local pandoc_docx, marker_err =
    make_pandoc_read_copy_with_empty_markers(docx)

  if not pandoc_docx then
    vim.fn.delete(temp_md)
    if vim.b[buf].wordvim_media_dir then
      vim.fn.delete(vim.b[buf].wordvim_media_dir, "rf")
      vim.b[buf].wordvim_media_dir = nil
    end
    vim.notify(
      "Word Vim: could not prepare DOCX for reading empty paragraphs:\n"
        .. tostring(marker_err),
      vim.log.levels.ERROR
    )
    return
  end

  local output = vim.fn.system({
    "pandoc",
    pandoc_docx,
    "--from=docx+styles",
    "--to=" .. markdown_format,
    "--wrap=none",
    "--extract-media=" .. media_dir,
    "--output=" .. temp_md,
  })

  vim.fn.delete(pandoc_docx)

  if vim.v.shell_error ~= 0 then
    vim.fn.delete(temp_md)
    if vim.b[buf].wordvim_media_dir then
      vim.fn.delete(vim.b[buf].wordvim_media_dir, "rf")
      vim.b[buf].wordvim_media_dir = nil
    end
    vim.notify(
      "Word Vim: DOCX conversion failed:\n" .. output,
      vim.log.levels.ERROR
    )
    return
  end

  local raw_lines = vim.fn.readfile(temp_md)
  vim.fn.delete(temp_md)

  -- Restore real inline Word tabs that were exposed to Pandoc as a safe
  -- temporary token on the read copy.  Literal TABs render as spacing in
  -- Neovim and are converted back to genuine <w:tab/> on save.
  for i, line in ipairs(raw_lines) do
    raw_lines[i] = (line or ""):gsub(INLINE_TAB_MARKER, "\t")
  end

  -- Pandoc can expose an image + real Word Caption as raw HTML <figure>.
  -- Convert that import artifact back to Word Vim's compact editor rows before
  -- paragraph-style cleanup and before crossrefs.restore_from_docx() runs.
  raw_lines = normalize_pandoc_figures(raw_lines)

  -- Collapse Pandoc's verbose representation of real Word REF/PAGEREF
  -- hyperlinks back to the compact text Word Vim shows in the editor.
  raw_lines = normalize_pandoc_crossrefs(raw_lines)

  -- Show underline with a compact editor marker (++text++) instead of the
  -- verbose Pandoc custom-style span.
  raw_lines = underline_to_editor_lines(raw_lines)

  -- Canonicalize image dimensions so 8cm does not drift to a long Pandoc
  -- inch + height attribute after repeated DOCX round-trips.
  raw_lines = normalize_pandoc_image_dimensions(raw_lines)

  -- Absolute Word extents cannot tell us whether the user originally entered
  -- width=50%. Restore that semantic percentage from Word Vim metadata stored
  -- on the corresponding wp:docPr node.
  raw_lines = images.restore_percent_widths(raw_lines, docx)

  local lines, assignments = clean_style_blocks(raw_lines)
  lines = strip_leaked_style_fences(lines)

  -- A real Word Heading can be exposed by Pandoc +styles as a generic
  -- custom-style fenced paragraph instead of Markdown '#'.  Word Vim uses
  -- the visible Markdown heading marker as the editor-side semantic form,
  -- so reconstruct it from the imported paragraph style before any row
  -- compaction happens.  This does not add/remove rows, therefore assignment
  -- row numbers remain valid.
  for _, item in ipairs(assignments) do
    local level = tostring(item.style or ""):match("^Heading%s+(%d)$")
    level = tonumber(level)
    if level and level >= 1 and level <= 9 then
      local idx = (tonumber(item.row) or 0) + 1
      local line = lines[idx] or ""
      line = line:gsub("^#+%s*", "")
      lines[idx] = string.rep("#", level) .. " " .. line
    end
  end

  -- Keep the Neovim view compact: Word paragraphs are adjacent
  -- editor rows, without visible empty separator rows.
  lines, assignments = compact_editor_lines(lines, assignments)

  -- Recover Word Vim tables from metadata rehydrated only in the disposable
  -- Pandoc copy and replace the pipe-table body with the editor display.
  local table_specs, table_row_map
  lines, table_specs, table_row_map = tables.extract(lines)
  if table_row_map then
    local remapped = {}
    for _, item in ipairs(assignments) do
      local row = table_row_map[item.row]
      if row ~= nil then remapped[#remapped + 1] = { row = row, style = item.style } end
    end
    assignments = remapped
  end

  -- Convert Pandoc Markdown list markers to Word Vim's readable
  -- four-level display (1 / 1.1 / ... and custom bullets).
  lines = lists.to_editor_lines(lines)

  -- Collapse a real Word TOC field back to one editor anchor row.
  -- The entries themselves are rendered as virtual lines by toc.lua.
  lines, assignments =
    toc.restore_editor_lines(
      buf,
      lines,
      assignments,
      docx
    )

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Do NOT create the TOC extmark yet.  Several restore steps below
  -- still rewrite buffer lines (notably list-level restoration and
  -- indent cleanup).  With right_gravity=true those rewrites can move
  -- the TOC anchor away from its title.  Keep only pending_open state
  -- until all structural buffer edits are complete.

  -- Pandoc may flatten nested DOCX list levels in Markdown.
  -- Restore the authoritative list level directly from w:ilvl so
  -- Neovim shows • / ◦ / ▪ / ▫ correctly after reopening.
  lists.load_levels_from_docx(buf, docx)

  for _, item in ipairs(assignments) do
    styles.set_paragraph_style(buf, item.row, item.style)
  end

  -- Read real leading Word TABs and paragraph left indents,
  -- then display both visually without arrow symbols.
  indents.load_from_docx(buf, docx)

  -- Pandoc may expose Word paragraph indentation as visible Markdown
  -- blockquote markers (">").  The true indent has already been read
  -- from word/document.xml, so remove those editor-only artifacts.
  indents.clean_editor_indent_markers(buf)

  -- Migrate literal leading TABs left by older Word Vim versions
  -- into hidden Word-tab metadata.
  indents.migrate_legacy_leading_tabs(buf)

  -- Mark the buffer before assigning markdown filetype so future
  -- Markdown-specific plugins can distinguish DOCX from real .md files.
  vim.b[buf].wordvim_docx = true
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].modified = false

  vim.b[buf].docx_original_file = docx
  apply_docx_buffer_profile(buf)

  -- Detect the document proofing language from w:lang.  This initializes
  -- spell checking and the EN/RU/RO statusline without changing the Windows
  -- keyboard layout merely because a document was opened.
  language.load_from_docx(buf, docx)

  -- Restore real Word page breaks and page layout settings.
  pagesettings.load_from_docx(buf, docx)

  -- Restore Word Caption / REF / PAGEREF metadata after Pandoc conversion.
  crossrefs.restore_from_docx(buf, docx)

  -- All buffer-rewriting import/cleanup passes are complete now.
  -- Create the TOC anchor only at this point so right_gravity=true can
  -- safely keep the title + virtual TOC together during normal editing
  -- (for example Shift+O above the TOC title) without the anchor being
  -- displaced by initialization-time whole-buffer rewrites.
  toc.finish_open(buf)

  -- v6.13 paragraph-style engine: every editor paragraph has explicit
  -- style metadata.  This also fills Normal for rows that Pandoc did not
  -- wrap in a custom-style block, while preserving imported Heading, Body
  -- Text, Caption, etc. markers that already exist.
  styles.ensure_explicit_styles(buf)

  vim.bo[buf].modified = false

  -- Apply the DOCX-local window profile (wrap, relative numbers,
  -- no sign column, and Word Vim statusline).
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    apply_docx_window_profile(buf, win)
  end

  -- Formatting/headings/lists are DOCX-buffer-local.
  formatting.attach(buf)
  styleui.attach(buf)
  images.attach(buf)

  -- Enable Word-like Enter / Shift+Enter behavior.
  paragraphs.attach(buf)

  -- Insert mode: Word TABs. Normal mode: paragraph indent.
  indents.attach(buf)

  -- Manual page breaks + page setup.
  pagebreaks.attach(buf)
  pagesettings.attach(buf)

  -- Table of Contents.
  toc.attach(buf)

  -- Figure/Table captions and cross-references.
  crossrefs.attach(buf)

  -- EN/RU/RO proofing + keyboard-layout switching.
  language.attach(buf)

  -- Word Vim shortcut Help.
  help.attach(buf)

  -- Cell text remains searchable and directly editable. Structural changes
  -- to table rows/delimiters are restored; those go through :WordTable.
  tables.attach_recovered(buf, table_specs or {})
  tables.protect(buf)

  -- Restore anchors after all whole-buffer import transformations.
  pagebreaks.load_from_docx(buf, docx)

  vim.notify(
    "Word Vim: DOCX opened. Word styles cached: " .. #cached_styles,
    vim.log.levels.INFO
  )
end

-- ============================================================
-- Save DOCX
-- ============================================================


local function validate_docx_with_pandoc(path)
  local temp_txt = vim.fn.tempname() .. ".txt"

  local output = vim.fn.system({
    "pandoc",
    path,
    "--to=plain",
    "--output=" .. temp_txt,
  })

  local ok = vim.v.shell_error == 0

  vim.fn.delete(temp_txt)

  if not ok then
    return false, output
  end

  return true
end


local function replace_file_safely(new_docx, original)
  local stage = original .. ".wordvim-new.docx"

  pcall(vim.fn.delete, stage)

  local copied, copy_err = copy_file(new_docx, stage)

  if not copied then
    return false,
      "could not create staging file: " .. tostring(copy_err),
      stage
  end

  local source = ps_escape(stage)
  local target = ps_escape(original)
  local swap_backup = ps_escape(original .. ".wordvim-swap-backup")

  local script = string.format([[
$source = '%s'
$target = '%s'
$swapBackup = '%s'
$lastError = ''

for ($i = 0; $i -lt 12; $i++) {
    try {
        if (Test-Path -LiteralPath $swapBackup) {
            Remove-Item -LiteralPath $swapBackup -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $target) {
            [System.IO.File]::Replace(
                $source,
                $target,
                $swapBackup,
                $true
            )
        }
        else {
            [System.IO.File]::Move($source, $target)
        }

        if (Test-Path -LiteralPath $swapBackup) {
            Remove-Item -LiteralPath $swapBackup -Force -ErrorAction SilentlyContinue
        }

        exit 0
    }
    catch {
        $lastError = $_.Exception.Message
        Start-Sleep -Milliseconds 250
    }
}

Write-Error $lastError
exit 1
]], source, target, swap_backup)

  local ok, output = run_powershell(script)

  if not ok then
    return false, output, stage
  end

  return true, nil, stage
end

local function save_docx(args)
  local buf = args.buf
  local original = vim.b[buf].docx_original_file

  if not original then
    return
  end

  -- Never let a displaced table range consume following paragraphs. Validate
  -- the exact model-derived table block before creating any output file.
  local tables_valid, table_validation_error = tables.validate(buf)
  if not tables_valid then
    vim.notify(
      "Word Vim: DOCX save stopped; table structure is inconsistent:\n"
        .. tostring(table_validation_error)
        .. "\nOpen the table with :WordTable or undo the structural edit.",
      vim.log.levels.ERROR
    )
    return
  end

  if not create_backup(original) then
    return
  end

  local temp_md = vim.fn.tempname() .. ".md"
  local temp_docx = vim.fn.tempname() .. ".docx"
  local temp_reference = vim.fn.tempname() .. ".docx"

  local copied, copy_err = copy_file(original, temp_reference)
  if not copied then
    vim.notify(
      "Word Vim: could not create reference DOCX:\n" .. tostring(copy_err),
      vim.log.levels.ERROR
    )
    return
  end

  -- v6.34: make sure any Word Vim fallback style actually referenced by
  -- the document (including Caption and Markdown headings) exists in the
  -- temporary reference DOCX. Existing document style definitions always
  -- win; only missing standard styles are materialized.
  styles.ensure_referenced_builtin_styles(buf)

  if not apply_style_changes(buf, temp_reference) then
    vim.fn.delete(temp_reference)
    return
  end

  local lines = build_markdown_for_save(buf)
  vim.fn.writefile(lines, temp_md)

  local output = vim.fn.system({
    "pandoc",
    temp_md,
    "--from=" .. markdown_format,
    "--to=docx",
    "--reference-doc=" .. temp_reference,
    "--output=" .. temp_docx,
  })

  vim.fn.delete(temp_md)
  vim.fn.delete(temp_reference)

  if vim.v.shell_error ~= 0 then
    vim.fn.delete(temp_docx)
    vim.notify(
      "Word Vim: DOCX save failed:\n" .. output,
      vim.log.levels.ERROR
    )
    return
  end

  -- Force editor headings to real Word Heading1..Heading9 paragraph styles.
  if not apply_heading_markers_to_docx(temp_docx) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Apply table metadata: repeating header rows, merges, borders and fills;
  -- then move the model out of body text into a standard custom property.
  local tables_ok, tables_error = tables.apply_to_docx(temp_docx)
  if not tables_ok then
    vim.fn.delete(temp_docx)
    vim.notify("Word Vim: could not apply table formatting:\n" .. tostring(tables_error), vim.log.levels.ERROR)
    return
  end

  -- Prevent styles.xml from growing on every save when Pandoc/reference-doc
  -- emits duplicate style definitions. Existing first definitions win.
  if not dedupe_word_styles(temp_docx) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Preserve semantic percentage image widths (for example width=50%).
  -- Pandoc/Word otherwise round-trip them as absolute physical extents only.
  if not images.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Inject real <w:tab/> elements and paragraph w:ind after Pandoc creates DOCX.
  if not indents.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Configure four-level ordered and bullet numbering in numbering.xml.
  if not lists.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Convert Word Vim marker paragraphs into real Word page breaks.
  if not pagebreaks.apply_to_docx(temp_docx) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Apply paper size, orientation and margins.
  if not pagesettings.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Replace caption/reference markers with real Word SEQ / REF / PAGEREF fields.
  if not crossrefs.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Replace the Word Vim TOC marker with a real Word TOC field.
  if not toc.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Persist the active Word Vim proofing language as real Word w:lang
  -- on document runs and in styles.xml defaults.
  if not language.apply_to_docx(temp_docx, buf) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Turn temporary marker text back into genuine empty Word paragraphs.
  -- The paragraph nodes themselves are kept, so blank paragraphs survive
  -- save -> close -> reopen instead of being treated as Markdown separators.
  if not remove_empty_paragraph_markers(temp_docx) then
    vim.fn.delete(temp_docx)
    return
  end

  -- Never replace the user's original file until Pandoc can read
  -- the final modified DOCX again.
  local valid, validation_error =
    validate_docx_with_pandoc(temp_docx)

  if not valid then
    vim.fn.delete(temp_docx)

    vim.notify(
      "Word Vim: final DOCX validation failed. Original file was NOT replaced.\n"
        .. tostring(validation_error),
      vim.log.levels.ERROR
    )
    return
  end

  local replaced, replace_err, stage =
    replace_file_safely(temp_docx, original)

  vim.fn.delete(temp_docx)

  if not replaced then
    vim.notify(
      "Word Vim: new DOCX was created, but the original file is locked.\n"
        .. tostring(replace_err)
        .. "\n\nThe new file was preserved here:\n"
        .. tostring(stage)
        .. "\n\nClose LibreOffice/OnlyOffice/Explorer preview and run :w again.",
      vim.log.levels.ERROR
    )
    return
  end

  vim.bo[buf].modified = false
  vim.notify("Word Vim: DOCX saved", vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "*.docx",
    callback = open_docx,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    pattern = "*.docx",
    callback = save_docx,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "*.docx",
    callback = function(args)
      if vim.b[args.buf].wordvim_docx then
        apply_docx_buffer_profile(args.buf)
        apply_docx_window_profile(args.buf, vim.api.nvim_get_current_win())
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    pattern = "*.docx",
    callback = function()
      restore_window_profile(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    pattern = "*.docx",
    callback = function(args)
      paragraphs.detach(args.buf)
      pagebreaks.detach(args.buf)
      pagesettings.detach(args.buf)
      toc.detach(args.buf)
      crossrefs.detach(args.buf)

      local media_dir = vim.b[args.buf].wordvim_media_dir
      if media_dir and media_dir ~= "" then
        pcall(vim.fn.delete, media_dir, "rf")
      end
    end,
  })


end

return M
