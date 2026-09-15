-- ============================================================
-- lua/wordvim/styles.lua
--
-- Hidden paragraph style storage + real Word style manager.
--
-- IMPORTANT:
-- extmarks only track positions.
-- Style names are stored in a Lua table keyed by extmark ID.
-- ============================================================

local M = {}

local namespace = vim.api.nvim_create_namespace("WordVimParagraphStyles")

-- Per-buffer state:
-- state[buf] = {
--   styles = {...},                  -- cached Word styles
--   mark_styles = {[extmark_id] = "Body Text"},
--   style_changes = {[style_id] = spec},
-- }
local state = {}

-- ============================================================
-- Built-in Word Vim style catalog (v6.34)
--
-- Existing DOCX styles ALWAYS win. These definitions are only
-- fallbacks for styles missing from word/styles.xml. A fallback
-- is written into the document only when the user actually applies
-- it. Text color is deliberately black for every Word Vim style.
-- ============================================================

local BUILTIN_STYLES = {
  { name = "Normal", id = "Normal", type = "paragraph", based_on = "", font = "Aptos", size = "12", bold = false, italic = false, underline = false, color = "000000", alignment = "left", before = "0", after = "8", quick_style = true },
  { name = "No Spacing", id = "NoSpacing", type = "paragraph", based_on = "Normal", font = "Aptos", size = "12", bold = false, italic = false, underline = false, color = "000000", alignment = "left", before = "0", after = "0", quick_style = true },
  { name = "Title", id = "Title", type = "paragraph", based_on = "Normal", font = "Aptos Display", size = "28", bold = false, italic = false, underline = false, color = "000000", alignment = "left", before = "0", after = "8", quick_style = true },
  { name = "Subtitle", id = "Subtitle", type = "paragraph", based_on = "Normal", font = "Aptos", size = "14", bold = false, italic = true, underline = false, color = "000000", alignment = "left", before = "0", after = "8", quick_style = true },
  { name = "Heading 1", id = "Heading1", type = "paragraph", based_on = "Normal", font = "Aptos Display", size = "20", bold = true, italic = false, underline = false, color = "000000", alignment = "left", before = "18", after = "6", outline_level = "0", quick_style = true },
  { name = "Heading 2", id = "Heading2", type = "paragraph", based_on = "Normal", font = "Aptos Display", size = "16", bold = true, italic = false, underline = false, color = "000000", alignment = "left", before = "12", after = "6", outline_level = "1", quick_style = true },
  { name = "Heading 3", id = "Heading3", type = "paragraph", based_on = "Normal", font = "Aptos Display", size = "14", bold = true, italic = false, underline = false, color = "000000", alignment = "left", before = "12", after = "4", outline_level = "2", quick_style = true },
  { name = "Heading 4", id = "Heading4", type = "paragraph", based_on = "Normal", font = "Aptos", size = "12", bold = true, italic = true, underline = false, color = "000000", alignment = "left", before = "10", after = "4", outline_level = "3", quick_style = true },
  { name = "Heading 5", id = "Heading5", type = "paragraph", based_on = "Normal", font = "Aptos", size = "11", bold = true, italic = false, underline = false, color = "000000", alignment = "left", before = "8", after = "3", outline_level = "4", quick_style = true },
  { name = "Heading 6", id = "Heading6", type = "paragraph", based_on = "Normal", font = "Aptos", size = "11", bold = false, italic = true, underline = false, color = "000000", alignment = "left", before = "8", after = "3", outline_level = "5", quick_style = true },
  { name = "Heading 7", id = "Heading7", type = "paragraph", based_on = "Normal", font = "Aptos", size = "10", bold = true, italic = false, underline = false, color = "000000", alignment = "left", before = "6", after = "2", outline_level = "6", quick_style = true },
  { name = "Heading 8", id = "Heading8", type = "paragraph", based_on = "Normal", font = "Aptos", size = "10", bold = false, italic = true, underline = false, color = "000000", alignment = "left", before = "6", after = "2", outline_level = "7", quick_style = true },
  { name = "Heading 9", id = "Heading9", type = "paragraph", based_on = "Normal", font = "Aptos", size = "10", bold = false, italic = false, underline = false, color = "000000", alignment = "left", before = "6", after = "2", outline_level = "8", quick_style = true },
  { name = "Body Text", id = "BodyText", type = "paragraph", based_on = "Normal", font = "Aptos", size = "12", bold = false, italic = false, underline = false, color = "000000", alignment = "left", before = "0", after = "6", quick_style = false },
  { name = "List Paragraph", id = "ListParagraph", type = "paragraph", based_on = "Normal", font = "Aptos", size = "12", bold = false, italic = false, underline = false, color = "000000", alignment = "left", before = "0", after = "0", quick_style = true },
  { name = "Quote", id = "Quote", type = "paragraph", based_on = "Normal", font = "Aptos", size = "11", bold = false, italic = true, underline = false, color = "000000", alignment = "left", before = "6", after = "6", quick_style = true },
  { name = "Intense Quote", id = "IntenseQuote", type = "paragraph", based_on = "Normal", font = "Aptos", size = "11", bold = true, italic = true, underline = false, color = "000000", alignment = "left", before = "8", after = "8", quick_style = true },
  { name = "Caption", id = "Caption", type = "paragraph", based_on = "Normal", font = "Aptos", size = "9", bold = false, italic = true, underline = false, color = "000000", alignment = "left", before = "0", after = "6", quick_style = true },
  { name = "TOC Heading", id = "TOCHeading", type = "paragraph", based_on = "Heading 1", font = "Aptos Display", size = "16", bold = true, italic = false, underline = false, color = "000000", alignment = "left", before = "12", after = "6", quick_style = true },
}

local function clone_style(style)
  local copy = {}
  for k, v in pairs(style) do
    copy[k] = v
  end
  return copy
end

local function find_builtin_style(name)
  if not name then
    return nil
  end
  local needle = tostring(name):lower()
  for _, style in ipairs(BUILTIN_STYLES) do
    if style.name:lower() == needle then
      return style
    end
  end
  return nil
end

local function get_state(buf)
  if not state[buf] then
    state[buf] = {
      styles = {},
      mark_styles = {},
      style_changes = {},
    }
  end
  return state[buf]
end

function M.reset_buffer(buf)
  state[buf] = {
    styles = {},
    mark_styles = {},
    style_changes = {},
  }
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
end

function M.set_cached_styles(buf, cached)
  local s = get_state(buf)
  local result = {}
  local seen_id = {}
  local seen_name = {}

  for _, style in ipairs(cached or {}) do
    local id_key = tostring(style.id or ""):lower()
    local name_key = tostring(style.type or ""):lower()
      .. "|"
      .. tostring(style.name or ""):lower():gsub("%s+", " ")

    if
      (id_key == "" or not seen_id[id_key])
      and (name_key == "|" or not seen_name[name_key])
    then
      table.insert(result, style)
      if id_key ~= "" then
        seen_id[id_key] = true
      end
      if name_key ~= "|" then
        seen_name[name_key] = true
      end
    end
  end

  s.styles = result
end

function M.get_cached_styles(buf)
  return get_state(buf).styles
end

function M.get_style_changes(buf)
  return get_state(buf).style_changes
end

local function find_style(buf, name)
  if not name then
    return nil
  end

  local needle = name:lower()
  for _, style in ipairs(get_state(buf).styles) do
    if style.name and style.name:lower() == needle then
      return style
    end
  end

  return nil
end

function M.find_style(buf, name)
  return find_style(buf, name)
end

local function delete_marks_on_row(buf, row)
  local s = get_state(buf)
  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    namespace,
    { row, 0 },
    { row, -1 },
    {}
  )

  for _, mark in ipairs(marks) do
    local id = mark[1]
    s.mark_styles[id] = nil
    pcall(vim.api.nvim_buf_del_extmark, buf, namespace, id)
  end
end

function M.clear_paragraph_style(buf, row)
  delete_marks_on_row(buf, row)
end

function M.set_paragraph_style(buf, row, style_name)
  delete_marks_on_row(buf, row)

  local id = vim.api.nvim_buf_set_extmark(
    buf,
    namespace,
    row,
    0,
    {
      -- Paragraph style belongs to the paragraph text, not to the
      -- numeric row that happened to contain it when DOCX was opened.
      -- With right_gravity=true, inserting a new row immediately before
      -- this paragraph (O, o on the previous row, etc.) moves the style
      -- marker together with the original paragraph.  The newly inserted
      -- paragraph therefore starts as Normal instead of stealing the
      -- following paragraph's Word style.
      right_gravity = true,
    }
  )

  get_state(buf).mark_styles[id] = style_name
  return id
end

function M.get_paragraph_style(buf, row)
  local s = get_state(buf)
  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    namespace,
    { row, 0 },
    { row, -1 },
    {}
  )

  for _, mark in ipairs(marks) do
    local id = mark[1]
    local style_name = s.mark_styles[id]
    if style_name then
      return style_name
    end
  end

  return nil
end


local function heading_style_from_text(line)
  local hashes = tostring(line or ""):match("^(#+)%s+")
  if hashes and #hashes >= 1 and #hashes <= 9 then
    return "Heading " .. #hashes
  end
  return nil
end

-- Ensure that every real Word paragraph has explicit style metadata.
-- Shift+Enter continuation rows are deliberately excluded because they are
-- part of the previous Word paragraph, not a separate paragraph.
--
-- Returns true when at least one missing marker was created.
function M.ensure_explicit_styles(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local changed = false
  local count = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for row = 0, count - 1 do
    local prev = row > 0 and (lines[row] or "") or ""
    local continuation = row > 0 and prev:match("%s%s$") ~= nil

    if not continuation and not M.get_paragraph_style(buf, row) then
      local line = lines[row + 1] or ""
      local inferred = heading_style_from_text(line) or "Normal"
      M.set_paragraph_style(buf, row, inferred)
      changed = true
    elseif continuation then
      -- A continuation row must never acquire an independent paragraph style.
      if M.get_paragraph_style(buf, row) then
        M.clear_paragraph_style(buf, row)
        changed = true
      end
    end
  end

  return changed
end

function M.set_new_paragraph_normal(buf, row)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local count = vim.api.nvim_buf_line_count(buf)
  if count <= 0 then
    return false
  end

  row = math.max(0, math.min(tonumber(row) or 0, count - 1))
  M.set_paragraph_style(buf, row, "Normal")
  return true
end

function M.get_style_map(buf)
  local s = get_state(buf)
  local result = {}

  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    namespace,
    0,
    -1,
    {}
  )

  for _, mark in ipairs(marks) do
    local id = mark[1]
    local row = mark[2]
    local style_name = s.mark_styles[id]
    if style_name then
      result[row] = style_name
    end
  end

  return result
end

local function current_paragraph_style()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1

  local hidden = M.get_paragraph_style(buf, row)
  if hidden then
    return hidden
  end

  local line = vim.fn.getline(".")
  local hashes = line:match("^(#+)%s+")

  if hashes and #hashes >= 1 and #hashes <= 9 then
    return "Heading " .. #hashes
  end

  return "Normal"
end

local function apply_style(style_name)
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1

  if M.apply_style_to_row(buf, row, style_name) then
    vim.notify("Word Vim style: " .. style_name, vim.log.levels.INFO)
  end
end


-- ============================================================
-- Public helpers used by the style UI
-- ============================================================

local function heading_style_from_line(line)
  local hashes = tostring(line or ""):match("^(#+)%s+")

  if hashes and #hashes >= 1 and #hashes <= 9 then
    return "Heading " .. #hashes
  end

  return nil
end

function M.get_effective_paragraph_style(buf, row)
  if not vim.api.nvim_buf_is_valid(buf) then
    return "Normal"
  end

  local hidden = M.get_paragraph_style(buf, row)
  if hidden then
    return hidden
  end

  local line = vim.api.nvim_buf_get_lines(
    buf,
    row,
    row + 1,
    false
  )[1] or ""

  return heading_style_from_line(line) or "Normal"
end

function M.get_paragraph_styles(buf)
  local result = {}
  local seen = {}

  local function visible_style_key(name)
    return vim.trim(tostring(name or "")):lower():gsub("%s+", " ")
  end

  -- Styles physically present in the DOCX come first and always win.
  -- Some Word/Pandoc round-trips can leave two paragraph-style records with
  -- the same display name but different internal IDs.  Showing both is
  -- confusing and can make Heading 1/2 appear duplicated in the panel.
  -- Keep the first document definition for each visible name.
  for _, style in ipairs(get_state(buf).styles) do
    if style.type == "paragraph" and style.name then
      local key = visible_style_key(style.name)
      if not seen[key] then
        table.insert(result, style)
        seen[key] = true
      end
    end
  end

  -- Add missing Word Vim defaults only to the UI/catalog. They are NOT
  -- injected into styles.xml until the user applies one.
  for _, builtin in ipairs(BUILTIN_STYLES) do
    if builtin.type == "paragraph" and not seen[visible_style_key(builtin.name)] then
      local copy = clone_style(builtin)
      copy.wordvim_builtin = true
      table.insert(result, copy)
    end
  end

  return result
end

function M.find_available_style(buf, name)
  return find_style(buf, name) or find_builtin_style(name)
end

function M.materialize_builtin_style(buf, name)
  local existing = find_style(buf, name)
  if existing then
    return existing, false
  end

  local builtin = find_builtin_style(name)
  if not builtin then
    return nil, false
  end

  -- Materialize a missing built-in parent first so w:basedOn always points
  -- to a real styleId rather than a display name. Existing document styles
  -- still take priority and are never rewritten by this step.
  if builtin.based_on and builtin.based_on ~= "" then
    if not find_style(buf, builtin.based_on) and find_builtin_style(builtin.based_on) then
      M.materialize_builtin_style(buf, builtin.based_on)
    end
  end

  local style = clone_style(builtin)
  style.wordvim_builtin = nil
  table.insert(get_state(buf).styles, style)

  local spec = clone_style(style)
  spec.bold = style.bold == true or style.bold == "yes"
  spec.italic = style.italic == true or style.italic == "yes"
  spec.underline = style.underline == true or style.underline == "yes"
  get_state(buf).style_changes[style.id] = spec

  vim.bo[buf].modified = true
  return style, true
end

function M.ensure_referenced_builtin_styles(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local needed = {}
  for _, style_name in pairs(M.get_style_map(buf)) do
    needed[tostring(style_name):lower()] = style_name
  end

  -- Headings can intentionally have no hidden style marker because their
  -- Markdown # prefix already carries the semantic heading level. Ensure the
  -- corresponding Word style exists before Pandoc uses the reference DOCX.
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local hashes = tostring(line):match("^(#+)%s+")
    if hashes and #hashes >= 1 and #hashes <= 9 then
      local name = "Heading " .. #hashes
      needed[name:lower()] = name
    end
  end

  for _, style_name in pairs(needed) do
    if not find_style(buf, style_name) and find_builtin_style(style_name) then
      M.materialize_builtin_style(buf, style_name)
    end
  end
end

function M.apply_style_to_row(buf, row, style_name)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local style = find_style(buf, style_name)

  if not style then
    style = M.materialize_builtin_style(buf, style_name)
  end

  if not style then
    vim.notify(
      "Word Vim: style not found: " .. tostring(style_name),
      vim.log.levels.ERROR
    )
    return false
  end

  if style.type ~= "paragraph" then
    vim.notify(
      "Word Vim: only paragraph styles can be applied here",
      vim.log.levels.WARN
    )
    return false
  end

  -- IMPORTANT:
  -- Replacing a complete Neovim line can move an extmark that sits at
  -- column 0 of the NEXT line onto the edited line. Paragraph styles
  -- are stored as extmarks, so changing one paragraph could therefore
  -- accidentally make the following paragraph lose its style and
  -- fall back to Normal.
  --
  -- Snapshot all hidden paragraph styles before editing the line and
  -- restore them afterwards at their original rows.
  local old_style_map = M.get_style_map(buf)

  local lines = vim.api.nvim_buf_get_lines(
    buf,
    row,
    row + 1,
    false
  )

  local line = lines[1] or ""
  local heading = style_name:match("^Heading%s+(%d)$")

  if heading then
    line = line:gsub("^#+%s*", "")

    vim.api.nvim_buf_set_lines(
      buf,
      row,
      row + 1,
      false,
      { string.rep("#", tonumber(heading)) .. " " .. line }
    )
  else
    line = line:gsub("^#+%s*", "")

    vim.api.nvim_buf_set_lines(
      buf,
      row,
      row + 1,
      false,
      { line }
    )
  end

  -- Rebuild the hidden-style extmarks from the snapshot.
  local s = get_state(buf)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  s.mark_styles = {}

  for saved_row, saved_style in pairs(old_style_map) do
    if saved_row ~= row then
      M.set_paragraph_style(buf, saved_row, saved_style)
    end
  end

  -- Apply the requested style to the edited paragraph.
  --
  -- IMPORTANT:
  -- "Normal" must also be stored explicitly. If we simply remove the
  -- hidden style marker, Pandoc may write the paragraph using its
  -- default body style (often "Body Text") when exporting to DOCX.
  --
  -- By keeping an explicit "Normal" marker, docx.lua can emit
  -- custom-style="Normal" during save.
  if not heading then
    M.set_paragraph_style(buf, row, style_name)
  end

  vim.bo[buf].modified = true

  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WordVimStyleChanged",
    modeline = false,
    data = {
      buf = buf,
      row = row,
      style = style_name,
    },
  })

  return true
end


local function normalize_bool(value)
  if type(value) == "boolean" then
    return value
  end

  value = tostring(value or ""):lower()
  return value == "y"
    or value == "yes"
    or value == "true"
    or value == "1"
    or value == "on"
end

function M.update_style_definition(buf, style_name, values)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false, "invalid document buffer"
  end

  local style = find_style(buf, style_name)

  if not style then
    return false, "style not found: " .. tostring(style_name)
  end

  values = values or {}

  local based_on = tostring(values.based_on or "")
  local font = tostring(values.font or "")
  local size = tostring(values.size or "")
  local color = tostring(values.color or ""):gsub("^#", "")
  local alignment = tostring(values.alignment or ""):lower()
  local before = tostring(values.before or "")
  local after = tostring(values.after or "")

  if size ~= "" and tonumber(size) == nil then
    return false, "Size must be a number or blank"
  end

  if before ~= "" and tonumber(before) == nil then
    return false, "Space before must be a number or blank"
  end

  if after ~= "" and tonumber(after) == nil then
    return false, "Space after must be a number or blank"
  end

  if
    alignment ~= ""
    and alignment ~= "left"
    and alignment ~= "center"
    and alignment ~= "right"
    and alignment ~= "justify"
  then
    return false, "Alignment: left / center / right / justify / blank"
  end

  -- DOCX also supports the special value "auto" for automatic
  -- text color. LibreOffice/Word commonly store Normal this way.
  -- Accept either "auto", blank, or a six-digit RGB HEX value.
  if
    color ~= ""
    and color:lower() ~= "auto"
    and not color:match("^[%x][%x][%x][%x][%x][%x]$")
  then
    return false,
      'Color must be "auto", blank, or six HEX digits (for example 1F4E79)'
  end

  local bold = normalize_bool(values.bold)
  local italic = normalize_bool(values.italic)
  local underline = normalize_bool(values.underline)

  style.based_on = based_on
  style.font = font
  style.size = size
  style.bold = bold and "yes" or "no"
  style.italic = italic and "yes" or "no"
  style.underline = underline and "yes" or "no"
  style.color = color
  style.alignment = alignment
  style.before = before
  style.after = after

  local s = get_state(buf)

  s.style_changes[style.id] = {
    name = style.name,
    id = style.id,
    type = style.type,
    based_on = based_on,
    font = font,
    size = size,
    bold = bold,
    italic = italic,
    underline = underline,
    color = color,
    alignment = alignment,
    before = before,
    after = after,
  }

  vim.bo[buf].modified = true

  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WordVimStyleDefinitionChanged",
    modeline = false,
    data = {
      buf = buf,
      style = style.name,
    },
  })

  return true
end

local function bool_from_text(value)
  value = tostring(value or ""):lower()
  return value == "y" or value == "yes" or value == "true" or value == "1"
end

local function edit_style(style)
  local buf = vim.api.nvim_get_current_buf()
  local s = get_state(buf)

  local based_on = vim.fn.input("Based on: ", style.based_on or "")
  local font = vim.fn.input("Font: ", style.font or "")
  local size = vim.fn.input("Size pt: ", style.size or "")
  local bold = vim.fn.input("Bold yes/no: ", style.bold or "no")
  local italic = vim.fn.input("Italic yes/no: ", style.italic or "no")
  local underline = vim.fn.input("Underline yes/no: ", style.underline or "no")
  local color = vim.fn.input("Color HEX: ", style.color or "")
  local alignment = vim.fn.input(
    "Alignment left/center/right/justify: ",
    style.alignment or ""
  )
  local before = vim.fn.input("Space before pt: ", style.before or "")
  local after = vim.fn.input("Space after pt: ", style.after or "")

  style.based_on = based_on
  style.font = font
  style.size = size
  style.bold = bool_from_text(bold) and "yes" or "no"
  style.italic = bool_from_text(italic) and "yes" or "no"
  style.underline = bool_from_text(underline) and "yes" or "no"
  style.color = color
  style.alignment = alignment
  style.before = before
  style.after = after

  s.style_changes[style.id] = {
    name = style.name,
    id = style.id,
    type = style.type,
    based_on = based_on,
    font = font,
    size = size,
    bold = bool_from_text(bold),
    italic = bool_from_text(italic),
    underline = bool_from_text(underline),
    color = color,
    alignment = alignment,
    before = before,
    after = after,
  }

  vim.bo[buf].modified = true

  vim.notify(
    "Word Vim: style changed in memory. Use :w to write it to DOCX.",
    vim.log.levels.INFO
  )
end

local function paragraph_style_candidates(buf)
  local result = {}
  for _, style in ipairs(M.get_paragraph_styles(buf)) do
    table.insert(result, style)
  end

  table.sort(result, function(a, b)
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)

  return result
end

function M.ensure_underline_style(buf)
  if find_style(buf, "Underline") then
    return
  end

  local s = get_state(buf)

  local style = {
    name = "Underline",
    id = "WV_Underline",
    type = "character",
    based_on = "",
    font = "",
    size = "",
    bold = "no",
    italic = "no",
    underline = "yes",
    color = "",
    alignment = "",
    before = "",
    after = "",
  }

  table.insert(s.styles, style)

  s.style_changes[style.id] = {
    name = style.name,
    id = style.id,
    type = style.type,
    based_on = "",
    font = "",
    size = "",
    bold = false,
    italic = false,
    underline = true,
    color = "",
    alignment = "",
    before = "",
    after = "",
  }
end

function M.setup()
  vim.api.nvim_create_user_command("WordStyle", function()
    vim.notify(
      "Current style: " .. current_paragraph_style(),
      vim.log.levels.INFO
    )
  end, {})

  vim.api.nvim_create_user_command("WordStyles", function()
    local buf = vim.api.nvim_get_current_buf()
    local candidates = paragraph_style_candidates(buf)

    if #candidates == 0 then
      vim.notify(
        "Word Vim: no cached paragraph styles. Close and reopen the DOCX.",
        vim.log.levels.ERROR
      )
      return
    end

    vim.ui.select(candidates, {
      prompt = "Word Style",
      format_item = function(style)
        return style.name
      end,
    }, function(choice)
      if choice then
        apply_style(choice.name)
      end
    end)
  end, {})

  vim.api.nvim_create_user_command("WordStyleApply", function(opts)
    local name = vim.trim(opts.args)
    if name == "" then
      vim.cmd("WordStyles")
      return
    end
    apply_style(name)
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("WordStyleEdit", function(opts)
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.trim(opts.args)

    if name ~= "" then
      local style = find_style(buf, name)
      if not style then
        style = M.materialize_builtin_style(buf, name)
      end
      if not style then
        vim.notify("Word Vim: style not found: " .. name, vim.log.levels.ERROR)
        return
      end
      edit_style(style)
      return
    end

    local candidates = paragraph_style_candidates(buf)

    vim.ui.select(candidates, {
      prompt = "Edit Word Style",
      format_item = function(style)
        return style.name
      end,
    }, function(choice)
      if choice then
        local style = find_style(buf, choice.name)
        if not style then
          style = M.materialize_builtin_style(buf, choice.name)
        end
        if style then
          edit_style(style)
        end
      end
    end)
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("WordStyleNew", function()
    local buf = vim.api.nvim_get_current_buf()
    local s = get_state(buf)

    local name = vim.fn.input("New style name: ")
    if name == "" then
      return
    end

    if find_style(buf, name) or find_builtin_style(name) then
      vim.notify(
        "Word Vim: style already exists or is available in the standard catalog",
        vim.log.levels.ERROR
      )
      return
    end

    local based_on = vim.fn.input("Based on [Normal]: ", "Normal")
    local font = vim.fn.input("Font (blank = inherited): ")
    local size = vim.fn.input("Size pt (blank = inherited): ")
    local bold = vim.fn.input("Bold yes/no [no]: ", "no")
    local italic = vim.fn.input("Italic yes/no [no]: ", "no")
    local underline = vim.fn.input("Underline yes/no [no]: ", "no")
    local color = vim.fn.input("Color HEX: ")
    local alignment = vim.fn.input("Alignment left/center/right/justify: ")
    local before = vim.fn.input("Space before pt: ")
    local after = vim.fn.input("Space after pt: ")

    local id = "WV_" .. vim.fn.sha256(name):sub(1, 12)

    local style = {
      name = name,
      id = id,
      type = "paragraph",
      based_on = based_on,
      font = font,
      size = size,
      bold = bool_from_text(bold) and "yes" or "no",
      italic = bool_from_text(italic) and "yes" or "no",
      underline = bool_from_text(underline) and "yes" or "no",
      color = color,
      alignment = alignment,
      before = before,
      after = after,
    }

    table.insert(s.styles, style)

    s.style_changes[id] = {
      name = name,
      id = id,
      type = "paragraph",
      based_on = based_on,
      font = font,
      size = size,
      bold = bool_from_text(bold),
      italic = bool_from_text(italic),
      underline = bool_from_text(underline),
      color = color,
      alignment = alignment,
      before = before,
      after = after,
    }

    vim.bo[buf].modified = true

    vim.notify(
      "Word Vim: new style created in memory. Use :w to save it.",
      vim.log.levels.INFO
    )
  end, {})
end

return M
