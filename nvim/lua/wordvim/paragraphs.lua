-- ============================================================
-- lua/wordvim/paragraphs.lua
--
-- Word-like paragraph behavior for DOCX buffers.
--
-- v6.13 invariant:
--   every REAL editor paragraph has explicit paragraph-style metadata.
--   New paragraphs created with Enter / o / O start as Normal.
--   Shift+Enter remains a line break inside the same Word paragraph.
-- ============================================================

local M = {}

local indents = require("wordvim.indents")
local styles = require("wordvim.styles")
local lists = require("wordvim.lists")

local attached = {}
local augroups = {}

local function is_wordvim_docx(buf)
  return vim.b[buf].docx_original_file ~= nil
end

local function notify_style_changed(buf, row, style)
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WordVimStyleChanged",
    modeline = false,
    data = {
      buf = buf,
      row = row,
      style = style or "Normal",
    },
  })
end

local function set_new_normal(buf, row, copy_indent_from)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local count = vim.api.nvim_buf_line_count(buf)
  if count <= 0 then
    return
  end

  row = math.max(0, math.min(row, count - 1))

  if copy_indent_from ~= nil then
    local source = math.max(0, math.min(copy_indent_from, count - 1))
    indents.copy_indent(buf, source, row)
  end

  styles.set_new_paragraph_normal(buf, row)
  notify_style_changed(buf, row, "Normal")
end

local function schedule_style_repair(buf)
  if vim.b[buf].wordvim_style_repair_pending then
    return
  end

  vim.b[buf].wordvim_style_repair_pending = true

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    vim.b[buf].wordvim_style_repair_pending = false

    if not is_wordvim_docx(buf) then
      return
    end

    if styles.ensure_explicit_styles(buf) then
      notify_style_changed(buf, vim.api.nvim_win_get_cursor(0)[1] - 1)
    end
  end)
end

function M.attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not is_wordvim_docx(buf) then
    return
  end

  if attached[buf] then
    return
  end

  attached[buf] = true

  -- Make imported Normal paragraphs explicit immediately.  This is harmless
  -- when docx.lua already performed the same pass and protects callers that
  -- attach this module independently.
  styles.ensure_explicit_styles(buf)

  -- Enter behaves like Word inside lists:
  --   * at the end of a non-empty list item -> continue the same list/level;
  --   * on an empty list item -> leave the list and create a Normal paragraph;
  --   * elsewhere -> create a new Normal Word paragraph.
  vim.keymap.set("i", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local old_row = cursor[1] - 1
    local col = cursor[2]
    local line = vim.api.nvim_get_current_line()
    local prefix, item = lists.continuation_prefix(line)
    local at_end = col >= #line

    if item and at_end then
      if vim.trim(item.body or "") == "" then
        -- Let Neovim create the next row first, then remove the empty list
        -- paragraph. The newly-created row shifts into its place and becomes
        -- a genuine Normal paragraph, matching Word's double-Enter behavior.
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end

          local count = vim.api.nvim_buf_line_count(buf)
          if old_row < count then
            vim.api.nvim_buf_set_lines(buf, old_row, old_row + 1, false, {})
          end

          local target = math.min(old_row, vim.api.nvim_buf_line_count(buf) - 1)
          if target >= 0 then
            styles.set_paragraph_style(buf, target, "Normal")
            notify_style_changed(buf, target, "Normal")
            pcall(vim.api.nvim_win_set_cursor, 0, { target + 1, 0 })
          end

          lists.renumber_buffer(buf)
        end)

        return "<CR>"
      end

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        local new_row = math.min(old_row + 1, vim.api.nvim_buf_line_count(buf) - 1)
        vim.api.nvim_buf_set_lines(buf, new_row, new_row + 1, false, { prefix or "" })
        styles.set_paragraph_style(buf, new_row, "List Paragraph")
        notify_style_changed(buf, new_row, "List Paragraph")
        lists.renumber_buffer(buf)

        local current = vim.api.nvim_buf_get_lines(buf, new_row, new_row + 1, false)[1] or ""
        pcall(vim.api.nvim_win_set_cursor, 0, { new_row + 1, #current })
      end)

      return "<CR>"
    end

    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local new_row = math.min(old_row + 1, vim.api.nvim_buf_line_count(buf) - 1)
        set_new_normal(buf, new_row, old_row)
      end
    end)

    return "<CR>"
  end, {
    buffer = buf,
    expr = true,
    noremap = true,
    silent = true,
    desc = "Word Vim: Word-like Enter / continue list",
  })

  -- Normal-mode o: native Vim open-below, then explicitly mark the new row as
  -- Normal.  Existing style extmarks below it follow their original paragraph.
  vim.keymap.set("n", "o", function()
    local old_row = vim.api.nvim_win_get_cursor(0)[1] - 1
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local new_row = math.min(old_row + 1, vim.api.nvim_buf_line_count(buf) - 1)
        set_new_normal(buf, new_row, nil)
      end
    end)
    return "o"
  end, {
    buffer = buf,
    expr = true,
    noremap = true,
    silent = true,
    desc = "Word Vim: open Normal paragraph below",
  })

  -- Normal-mode O: the original paragraph moves down; right_gravity=true keeps
  -- its style attached to it.  The new row above is explicitly Normal.
  vim.keymap.set("n", "O", function()
    local old_row = vim.api.nvim_win_get_cursor(0)[1] - 1
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        set_new_normal(buf, old_row, nil)
      end
    end)
    return "O"
  end, {
    buffer = buf,
    expr = true,
    noremap = true,
    silent = true,
    desc = "Word Vim: open Normal paragraph above",
  })

  -- Shift+Enter: hard line break INSIDE the same Word paragraph.  No separate
  -- style marker is created for the continuation row.
  local function line_break()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2]
    local style = styles.get_effective_paragraph_style(buf, row) or "Normal"
    -- Insert directly: native Enter can strip trailing spaces via autoindent.
    -- Do not pass through completion, list continuation or paragraph mappings.
    vim.api.nvim_buf_set_text(buf, row, col, row, col, { "  ", "" })
    styles.set_paragraph_style(buf, row, style)
    styles.ensure_explicit_styles(buf)
    vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
    notify_style_changed(buf, row, style)
  end
  vim.keymap.set("i", "<S-CR>", line_break, {
    buffer = buf, silent = true, desc = "Word Vim: line break inside paragraph",
  })
  vim.keymap.set("i", "<S-kEnter>", line_break, {
    buffer = buf, silent = true, desc = "Word Vim: keypad line break inside paragraph",
  })
  -- Portable alternative when a terminal sends Enter for Shift+Enter.
  vim.keymap.set("i", "<C-g><CR>", line_break, {
    buffer = buf, silent = true, desc = "Word Vim: line break inside paragraph",
  })

  local group = vim.api.nvim_create_augroup("WordVimParagraphs_" .. tostring(buf), { clear = true })
  augroups[buf] = group

  -- Covers paste, :put, deletions and other edits that do not go through our
  -- Enter/o/O mappings.  Run after textlock has ended; only missing paragraph
  -- style markers are filled, existing Word styles are preserved.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    buffer = buf,
    callback = function()
      schedule_style_repair(buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      attached[buf] = nil
      augroups[buf] = nil
    end,
  })
end

function M.detach(buf)
  attached[buf] = nil
  local group = augroups[buf]
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    augroups[buf] = nil
  end
end

-- Pandoc writes hard breaks as a single trailing backslash. The editor's
-- paragraph model uses two trailing spaces. Preserve escaped literal slashes
-- and fenced code; otherwise a save/reopen creates an extra Word paragraph.
function M.normalize_import(lines)
  local result, fence_char, fence_size = {}, nil, nil
  for i,line in ipairs(lines) do
    local marker=line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
    if marker then
      if not fence_char then fence_char,fence_size=marker:sub(1,1),#marker
      elseif marker:sub(1,1)==fence_char and #marker>=fence_size then fence_char,fence_size=nil,nil end
      result[i]=line
    elseif not fence_char then
      local slashes=line:match('(\\+)$')
      result[i]=slashes and #slashes%2==1 and (line:sub(1,-2)..'  ') or line
    else result[i]=line end
  end
  return result
end
function M.setup()
  vim.api.nvim_create_user_command("WordTerminalSetup", function(opts)
    local module_path = debug.getinfo(1, "S").source:sub(2)
    local script = vim.fn.fnamemodify(module_path, ":p:h:h:h") .. "/tools/Enable-ShiftEnter.ps1"
    local windows = vim.fn.has("win32") == 1
    local shell = windows and "powershell" or "powershell.exe"
    if vim.fn.executable(shell) == 0 then
      vim.notify("Windows Terminal setup requires Windows PowerShell. Use Ctrl+g Enter or configure your terminal to send CSI-u Shift+Enter.", vim.log.levels.ERROR)
      return
    end
    if not windows then
      script = vim.trim(vim.fn.system({"wslpath", "-w", script}))
      if vim.v.shell_error ~= 0 then vim.notify("Cannot translate script path for Windows", vim.log.levels.ERROR); return end
    end
    local command = {shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Apply"}
    if opts.fargs[1] then vim.list_extend(command, {"-SettingsPath", opts.fargs[1]}) end
    local output = vim.fn.system(command)
    vim.notify(output, vim.v.shell_error == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
  end, {nargs = "?", complete = "file", desc = "Configure Windows Terminal Shift+Enter (backs up settings)"})
  vim.api.nvim_create_user_command("WordKeyCheck", function()
    vim.api.nvim_echo({{"Press Shift+Enter once (Esc cancels): ", "Question"}}, false, {})
    vim.cmd("redraw")
    local key = vim.fn.getcharstr()
    local modifiers = vim.fn.getcharmod()
    local label = vim.fn.keytrans(key)
    if label == "<Esc>" then return end
    local shift = math.floor(modifiers / 2) % 2 == 1
    local message = "Received: " .. label .. "; modifiers=" .. modifiers
    if (label == "<CR>" or label == "<NL>") and not shift then
      message = message .. "\nTerminal sent ordinary Enter; Shift is missing. "
        .. ((require("wordvim.runtime").windows() or vim.env.WT_SESSION)
          and "Windows Terminal: run :WordTerminalSetup, then restart Neovim. "
          or "Configure this terminal to send CSI-u Shift+Enter. ")
        .. "Portable DOCX shortcut: Ctrl+g then Enter."
    else
      message = message .. "\nUse Shift+Enter in Insert mode. If it still fails, report this result."
    end
    vim.notify(message, vim.log.levels.INFO)
  end, {desc = "Check the actual Shift+Enter key received from the terminal"})
end

return M
