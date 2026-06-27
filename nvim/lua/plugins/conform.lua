local conform = require("conform")
conform.setup({
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
    format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true,
    }
})
vim.keymap.set("n","<leader>f",
    function()
        conform.format({
            async = true,
            lsp_fallback=true,
        })
    end,
    {desc="Format file"}
)
