local lspconfig = require("lspconfig")

-- общие capabilities (cmp, если добавишь позже)
local capabilities = vim.lsp.protocol.make_client_capabilities()

-- общий on_attach
local on_attach = function(client, bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }

  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
end

-- Lua
lspconfig.lua_ls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
  settings = {
    Lua = {
      diagnostics = {
        globals = { "vim" },
      },
    },
  },
})

-- Python
lspconfig.pyright.setup({
  capabilities = capabilities,
  on_attach = on_attach,
})

lspconfig.ts_ls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
})

-- ❌ НИКАКОГО jdtls здесь нет

--local lspconfig = require("lspconfig")
--
-- путь до jdtls, установленного Mason
--local jdtls_path = vim.fn.stdpath("data") .. "/mason/bin/jdtls"
--
--lspconfig.jdtls.setup{
--    cmd = { jdtls_path },
--    filetypes = { "java" },
--    root_dir = lspconfig.util.root_pattern(".git", "mvnw", "gradlew", "pom.xml", "build.gradle"),
--    settings = {
--        java = {
--            signatureHelp = { enabled = true },
--            contentProvider = { preferred = "fernflower" },
--        }
--    },
--    on_attach = function(client, bufnr)
--        -- тут можно настроить горячие клавиши для java
--        local bufmap = function(mode, lhs, rhs)
--            vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, { noremap=true, silent=true })
--        end
--        bufmap("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>")
--        bufmap("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>")
--    end
--}

--local jdtls = require("jdtls")

--local mason_path = vim.fn.stdpath("data") .. "/mason"
--local jdtls_path = mason_path .. "/packages/jdtls"

-- Find launcher jar dynamically (safe across updates)
--local launcher = vim.fn.glob(
--  jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar"
--)

--local config = {
--  cmd = {
--    "/opt/jdk21/bin/java", -- adjust if needed
--    "-Declipse.application=org.eclipse.jdt.ls.core.id1",
--    "-Dosgi.bundles.defaultStartLevel=4",
--    "-Declipse.product=org.eclipse.jdt.ls.core.product",
--    "-Dlog.protocol=true",
--    "-Dlog.level=ALL",
--    "-Xms512m",
--    "-Xmx2048m",

--    "--add-modules=ALL-SYSTEM",
--    "--add-opens", "java.base/java.util=ALL-UNNAMED",
--    "--add-opens", "java.base/java.lang=ALL-UNNAMED",

--    "-jar", launcher,

--    -- 🔴 THIS IS THE IMPORTANT PART
--    "-configuration", jdtls_path .. "/config_linux_arm",

--    "-data", vim.fn.expand("~/.cache/jdtls-workspace"),
-- },

--  root_dir = require("jdtls.setup").find_root({
--    "pom.xml",
--    "build.gradle",
--    ".git",
--  }),

--  settings = {
--    java = {
--      configuration = {
--        runtimes = {
--          {
--            name = "JavaSE-21",
--            path = "/opt/jdk21",
--          },
--        },
--      },
--    },
--  },
--}

--jdtls.start_or_attach(config)

