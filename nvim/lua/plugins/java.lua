--local capabilities = require("cmp_nvim_lsp").default_capabilities()
local jdtls = require("jdtls")
local jdtls_path = vim.fn.stdpath("data") .. "/mason/packages/jdtls"

local launcher = vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar")
local config = jdtls_path .. "/config_linux_arm"

local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. project_name

local root_dir = require("jdtls.setup").find_root({
  ".git",
  "mvnw",
  "gradlew",
  "pom.xml",
  "build.gradle",
})

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

jdtls.start_or_attach({
  cmd = cmd,
  root_dir = root_dir,
  --capabilities = capabilities,
  settings = {
    java = {
      signatureHelp = { enabled = true },
      contentProvider = { preferred = "fernflower" },
    },
  },
})
