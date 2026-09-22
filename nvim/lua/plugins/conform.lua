local conform = require("conform")
conform.setup({
    formatters = { ["google-java-format"] = { prepend_args = { "--aosp" } } },
    formatters_by_ft = {
        java = {"google-java-format"},
        javascript = {"prettier"},
        javascriptreact = {"prettier"},
        typescript = {"prettier"},
        typescriptreact = {"prettier"},
        css = {"prettier"},
        html = {"prettier"},
        lua = {"stylua"},
        python = {"black"},
    },
    format_on_save = function(bufnr)
        if vim.b[bufnr].wordvim_docx then
            return nil
        end
        return {
            timeout_ms = 2000,
            lsp_fallback = true,
        }
    end
})
vim.keymap.set("n","<leader>f",
    function()
        if vim.b.wordvim_docx then
            vim.notify("Word Vim: Conform is disabled for DOCX buffers", vim.log.levels.INFO)
            return
        end
        conform.format({
            async = true,
            lsp_fallback=true,
        })
    end,
    {desc="Format file"}
)

