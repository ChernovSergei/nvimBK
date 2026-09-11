-- ============================================================
-- lua/wordvim/init.lua
-- ============================================================

local M = {}

local docx = require("wordvim.docx")
local formatting = require("wordvim.formatting")
local tables = require("wordvim.tables")
local lists = require("wordvim.lists")
local styles = require("wordvim.styles")
local images = require("wordvim.images")
local paragraphs = require("wordvim.paragraphs")
local indents = require("wordvim.indents")
local styleui = require("wordvim.styleui")
local pagebreaks = require("wordvim.pagebreaks")
local pagesettings = require("wordvim.pagesettings")
local toc = require("wordvim.toc")
local crossrefs = require("wordvim.crossrefs")

function M.setup()
  docx.setup()
  formatting.setup()
  tables.setup()
  lists.setup()
  styles.setup()
  images.setup()
  paragraphs.setup()
  indents.setup()
  styleui.setup()
  pagebreaks.setup()
  pagesettings.setup()
  toc.setup()
  crossrefs.setup()
end

return M
