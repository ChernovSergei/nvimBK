local null_ls = require("null-ls")

null_ls.setup({
    sources = {
        --Java
        null_ls.builtins.formatting.google_java_format,

        --JavaScript/ TypeScript
        null_ls.builtins.formatting.prettier,

        --Lua
        null_ls.builtins.formatting.stylua,

        --Python
        null_ls.builtins.formatting.black,

        -- diagnostics (optional)
        -- null_ls.builtins.diagnostics.eslint,
    },

    on_attach = function (client, bufnr)
        if client.supports_method("textDocument/formatting") then
           vim.keymap.set("n", "<leader>f", function ()
               vim.lsp.buf.format({ async = true })
           end, { buffer = bufnr, desc = "Format file"})
        end
    end,
})
