local jdtls = require("jdtls")
local capabilities = require("cmp_nvim_lsp").default_capabilities()

local jdtls_path = vim.fn.stdpath("data") .. "/mason/packages/jdtls"
local launcher = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar")
local config = jdtls_path .. "/config_linux"
if vim.fn.isdirectory(config) == 0 then
    config = jdtls_path .. "/config_linux_arm"
end

local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. project_name

local root_dir = require("jdtls.setup").find_root({
  ".git",
  "mvnw",
  "gradlew",
  "pom.xml",
  "build.gradle",
})

if root_dir == nil then
    return
end

local cmd = {
  "java",
  "-Declipse.application=org.eclipse.jdt.ls.core.id1",
  "-Dosgi.bundles.defaultStartLevel=4",
  "-Declipse.product=org.eclipse.jdt.ls.core.product",
  "-Dlog.protocol=true",
  "-Dlog.level=ALL",
  "-Xms1g",
  "--add-modules=ALL-SYSTEM",
  "--add-opens", "java.base/java.util=ALL-UNNAMED",
  "--add-opens", "java.base/java.lang=ALL-UNNAMED",

  "-jar", launcher,
  "-configuration", config,
  "-data", workspace_dir,
}

local bundles = {
    vim.fn.glob(
        vim.fn.stdpath("data")
        .. "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar"
        ),
}

vim.list_extend(
    bundles,
    vim.split(
        vim.fn.glob(
            vim.fn.stdpath("data")
            .."/mason/packages/java-test/extension/server/*.jar"
        ),
        "\n"
    )
    )

jdtls.start_or_attach({
  cmd = cmd,
  root_dir = root_dir,
  capabilities = capabilities,
  settings = {
    java = {
      signatureHelp = { enabled = true },
      contentProvider = { preferred = "fernflower" },
      format = { enabled = true },
    },
  },
  init_options = {
      bundles = bundles,
  }
})

local opts = { noremap = true, silent = true, buffer = true }

--Organize imports
vim.keymap.set("n", "<leader>oi", jdtls.organize_imports, opts)

--Extract
vim.keymap.set("n", "<leader>em", jdtls.extract_method, opts)
vim.keymap.set("n", "<leader>ev", jdtls.extract_variable, opts)
vim.keymap.set("n", "<leader>ec", jdtls.extract_constant, opts)

--Test
vim.keymap.set("n", "<leader>tt", jdtls.test_class, opts)
vim.keymap.set("n", "<leader>tn", jdtls.test_nearest_method, opts)
