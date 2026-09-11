-- ============================================================
-- lua/wordvim/tables.lua
-- ============================================================

local M = {}

local function insert_table(rows, columns)
  rows = tonumber(rows) or 3
  columns = tonumber(columns) or 3

  rows = math.max(1, math.min(rows, 50))
  columns = math.max(1, math.min(columns, 20))

  local result = {}

  local header = "|"
  for column = 1, columns do
    header = header .. " Column " .. column .. " |"
  end
  table.insert(result, header)

  local separator = "|"
  for _ = 1, columns do
    separator = separator .. " --- |"
  end
  table.insert(result, separator)

  for _ = 1, rows do
    local row = "|"
    for _ = 1, columns do
      row = row .. "   |"
    end
    table.insert(result, row)
  end

  vim.api.nvim_put(result, "l", true, true)
end

function M.setup()
  vim.api.nvim_create_user_command("WordTable", function(opts)
    insert_table(opts.fargs[1], opts.fargs[2])
  end, {
    nargs = "*",
    desc = "Insert a Markdown table for DOCX export",
  })
end

return M
