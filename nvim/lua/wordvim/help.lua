-- ============================================================
-- lua/wordvim/help.lua
--
-- Floating Word Vim help window.
-- ============================================================

local M = {}

local help_buf = nil
local help_win = nil

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function close_help()
  if valid_win(help_win) then
    pcall(vim.api.nvim_win_close, help_win, true)
  end

  help_win = nil
  help_buf = nil
end

local function lines()
  return {
    "WORD VIM HELP",
    "=============",
    "",
    "GENERAL",
    "-------",
    "Space w h            Open / close this Help window",
    ":WordHelp            Open / close this Help window",
    ":w                   Save DOCX",
    "q / Esc              Close Help window",
    "",
    "PARAGRAPHS",
    "----------",
    "Enter                New Word paragraph",
    "Shift+Enter          Line break inside same Word paragraph",
    "o                    New paragraph below",
    "O                    New paragraph above",
    "dd                   Delete paragraph with Word Vim metadata",
    "",
    "FORMATTING  (Visual mode)",
    "-------------------------",
    "Space b              Bold",
    "Space i              Italic",
    "Space u              Underline (++text++ in editor)",
    "Space s              Strikeout",
    "",
    "HEADINGS",
    "--------",
    "Space 1              Heading 1",
    "Space 2              Heading 2",
    "Space 3              Heading 3",
    "Space 4              Heading 4",
    "Space 5              Heading 5",
    "Space 6              Heading 6",
    "",
    "LISTS",
    "-----",
    "Space l b            Bullet list / toggle",
    "Space l n            Numbered list / toggle",
    "Visual + Space l b   Bullet list for selection",
    "Visual + Space l n   Numbered list for selection",
    "Enter                Continue same list/level at end of item",
    "Enter on empty item  Exit list -> Normal paragraph",
    "Space l x            Exit/cancel current list item",
    "Tab                  Increase list level when on list item",
    "Shift+Tab            Decrease list level when on list item",
    "",
    "WORD TABS / PARAGRAPH INDENT",
    "----------------------------",
    "Insert: Tab          Insert genuine Word TAB at cursor",
    "Insert: Shift+Tab    Remove preceding / leading Word TAB",
    "Insert: Backspace    At column 0: remove hidden leading Word TAB",
    "Normal: Tab          Increase paragraph indent",
    "Normal: Shift+Tab    Decrease paragraph indent",
    "",
    "STYLES",
    "------",
    "Space w s            Toggle both Style panels",
    "Space w l            Toggle left style gutter",
    "Space w r            Toggle right style list",
    "Style list: Enter/e  Edit selected style",
    "Style gutter: Enter  Edit style number",
    "Style editor: Ctrl+s Save changes",
    "Style editor: q/Esc  Close editor",
    ":WordStyle           Show current paragraph style",
    ":WordStyles          Choose/apply paragraph style",
    ":WordStyleApply ...  Apply style by name",
    ":WordStyleEdit ...   Edit style by name",
    ":WordStyleNew        Create a new style",
    ":WordStyleWidth 32   Set right panel width",
    ":WordStyleGutterWidth 4  Set left gutter width",
    "",
    "PAGES",
    "-----",
    "Space p b            Insert page break before paragraph",
    "Space p d            Delete page break before paragraph",
    "Space p s            Page Setup",
    "Page Setup: Enter/e  Edit selected setting",
    "Page Setup: Ctrl+s   Save and close",
    "Page Setup: q/Esc    Cancel",
    ":WordPageRecalculate Recalculate virtual page boundaries",
    "",
    "TABLE OF CONTENTS",
    "-----------------",
    "Space t c            Insert Table of Contents",
    "Space t d            Delete Table of Contents",
    "Space t o            Open / close Contents window",
    "Contents: Enter/e    Jump to heading",
    "Contents: q/Esc      Close Contents window",
    ":WordTOCRefresh      Refresh Table of Contents",
    "",
    "TABLES",
    "------",
    ":WordTable           Create/edit table in floating editor",
    ":WordTable 5 4       Create a 5 x 4 table",
    "  Cell text is searchable/editable; structure uses the editor",
    "  Enter edit cell | Space + M merge | U split",
    "  S cell style | B cell borders | L table borders",
    "  H header rows | A/D row | I/X column | R delete | W save | Q cancel",
    "",
    "IMAGES",
    "------",
    "Space i i            Open Neo-tree image picker",
    "Image picker: Enter  Open folder / insert selected image",
    "Image picker: q/Esc  Cancel image picker",
    ":WordImageWidth 8cm  Set image width",
    ":WordImageScale 50   Set image width to 50%",
    ":WordImageResize 125 Resize current width to 125%",
    ":WordImageRotate 90  Rotate 90 / 180 / 270 degrees",
    ":WordImageReset      Reset natural image size",
    "",
    "CAPTIONS / CROSS-REFERENCES",
    "---------------------------",
    "Space c f            Insert Figure caption",
    "Space c t            Insert Table caption",
    "Space r f            Insert Figure reference",
    "Space r t            Insert Table reference",
    "Reference picker: Enter/e  Select item",
    "Reference picker: q/Esc    Cancel",
    "",
    "LANGUAGE",
    "--------",
    "Space l e            Insert language: English",
    "Space l r            Insert language: Russian",
    "Space l o            Insert language: Romanian",
    ":WordLanguage en     DOCX proofing language: English",
    ":WordLanguage ru     DOCX proofing language: Russian",
    ":WordLanguage ro     DOCX proofing language: Romanian",
    "",
    "WINDOW NAVIGATION  (standard Neovim)",
    "------------------------------------",
    "Ctrl+w h             Window left",
    "Ctrl+w j             Window down",
    "Ctrl+w k             Window up",
    "Ctrl+w l             Window right",
    "",
    "Tip: Space is the <leader> key in this configuration.",
  }
end

local function add_highlights(buf, content)
  local ns = vim.api.nvim_create_namespace("WordVimHelp")

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for i, line in ipairs(content) do
    local row = i - 1

    if i == 1 then
      vim.api.nvim_buf_add_highlight(buf, ns, "Title", row, 0, -1)
    elseif line:match("^[A-Z][A-Z /%-()]+$") then
      vim.api.nvim_buf_add_highlight(buf, ns, "Function", row, 0, -1)
    elseif line:match("^[:A-Za-z].-%s%s+") or line:match("^Space ") or line:match("^Visual ") or line:match("^Insert:") or line:match("^Normal:") then
      local stop = line:find("%s%s+")
      if stop then
        vim.api.nvim_buf_add_highlight(buf, ns, "Special", row, 0, stop - 1)
      end
    end
  end
end

function M.open()
  if valid_win(help_win) then
    close_help()
    return
  end

  local content = lines()
  local ui = vim.api.nvim_list_uis()[1]
  local columns = (ui and ui.width) or vim.o.columns
  local rows = (ui and ui.height) or vim.o.lines

  local max_line = 0
  for _, line in ipairs(content) do
    max_line = math.max(max_line, vim.fn.strdisplaywidth(line))
  end

  local width = math.min(math.max(62, max_line + 4), math.max(40, columns - 6))
  local height = math.min(#content, math.max(12, rows - 6))
  local row = math.max(0, math.floor((rows - height) / 2) - 1)
  local col = math.max(0, math.floor((columns - width) / 2))

  help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, content)
  vim.bo[help_buf].buftype = "nofile"
  vim.bo[help_buf].bufhidden = "wipe"
  vim.bo[help_buf].swapfile = false
  vim.bo[help_buf].modifiable = false
  vim.bo[help_buf].filetype = "wordvimhelp"

  help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Word Vim Help ",
    title_pos = "center",
  })

  vim.wo[help_win].wrap = false
  vim.wo[help_win].cursorline = true
  vim.wo[help_win].number = false
  vim.wo[help_win].relativenumber = false
  vim.wo[help_win].signcolumn = "no"
  vim.wo[help_win].foldcolumn = "0"

  add_highlights(help_buf, content)

  local opts = { buffer = help_buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", close_help, opts)
  vim.keymap.set("n", "<Esc>", close_help, opts)
  vim.keymap.set("n", "<leader>wh", close_help, opts)
  vim.keymap.set("n", "gg", "gg", opts)
  vim.keymap.set("n", "G", "G", opts)
end

function M.attach(buf)
  vim.keymap.set("n", "<leader>wh", M.open, {
    buffer = buf,
    silent = true,
    desc = "Word Vim: Help",
  })
end

function M.setup()
  vim.api.nvim_create_user_command("WordHelp", M.open, {
    desc = "Open or close Word Vim shortcut help",
  })
end

return M
