local lspconfig = require("lspconfig")

-- путь до jdtls, установленного Mason
local jdtls_path = vim.fn.stdpath("data") .. "/mason/bin/jdtls"

lspconfig.jdtls.setup{
    cmd = { jdtls_path },
    filetypes = { "java" },
    root_dir = lspconfig.util.root_pattern(".git", "mvnw", "gradlew", "pom.xml", "build.gradle"),
    settings = {
        java = {
            signatureHelp = { enabled = true },
            contentProvider = { preferred = "fernflower" },
        }
    },
    on_attach = function(client, bufnr)
        -- тут можно настроить горячие клавиши для java
        local bufmap = function(mode, lhs, rhs)
            vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, { noremap=true, silent=true })
        end
        bufmap("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>")
        bufmap("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>")
    end
}
