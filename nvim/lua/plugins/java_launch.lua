-- Build JDTLS arguments independently of the active buffer for regression tests.
local M = {}
function M.build(root, opts)
  opts = opts or {}
  local data = opts.data or vim.fn.stdpath('data')
  local mason = opts.mason_root or data .. '/mason'
  if not opts.data and not opts.mason_root then
    local ok, settings = pcall(require, 'mason.settings')
    if ok and settings.current and settings.current.install_root_dir then
      mason = settings.current.install_root_dir
    end
  end
  local base = mason .. '/packages/jdtls'
  local osname = opts.os or (vim.uv or vim.loop).os_uname().sysname
  local arch = opts.arch or (vim.uv or vim.loop).os_uname().machine
  local platform = osname == 'Windows_NT' and 'win' or osname == 'Darwin' and 'mac' or 'linux'
  local config = base .. '/config_' .. platform
  if (arch == 'aarch64' or arch == 'arm64') and vim.fn.isdirectory(config .. '_arm') == 1 then
    config = config .. '_arm'
  end
  if vim.fn.isdirectory(config) == 0 then
    config = mason .. '/share/jdtls/config'
  end
  if vim.fn.isdirectory(config) == 0 then
    return nil, 'JDTLS configuration missing under ' .. mason .. '. Run :MasonInstall jdtls, wait for completion, then reopen Neovim. See :WordJavaStatus.'
  end
  local jars = vim.fn.glob(base .. '/plugins/org.eclipse.equinox.launcher_*.jar', false, true)
  if #jars == 0 then
    local shared = mason .. '/share/jdtls/plugins/org.eclipse.equinox.launcher.jar'
    if vim.fn.filereadable(shared) == 1 then jars = {shared} end
  end
  if #jars ~= 1 then
    return nil, 'Expected one JDTLS launcher JAR, found ' .. #jars .. '. Reinstall jdtls using :Mason.'
  end
  local java = opts.java or vim.g.wordvim_java_cmd
  if not java or java == '' then
    local home = vim.env.JAVA_HOME
    local candidate = home and (home .. '/bin/' .. (platform == 'win' and 'java.exe' or 'java'))
    java = candidate and vim.fn.executable(candidate) == 1 and candidate or 'java'
  end
  if vim.fn.executable(java) ~= 1 then return nil, 'Java executable not found: ' .. java end
  local normalized = vim.fs.normalize(root):gsub('/+$', '')
  if platform == 'win' then normalized = normalized:lower() end
  local name = vim.fn.fnamemodify(normalized, ':t'):gsub('[^%w_.-]', '_')
  local workspace = data .. '/jdtls-workspace/' .. name .. '-' .. vim.fn.sha256(normalized):sub(1,16)
  local bundles = {}
  for _,pattern in ipairs({
    mason .. '/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar',
    mason .. '/packages/java-test/extension/server/*.jar',
  }) do
    for _,jar in ipairs(vim.fn.glob(pattern,false,true)) do
      local filename = vim.fn.fnamemodify(jar, ':t')
      if filename ~= 'com.microsoft.java.test.runner-jar-with-dependencies.jar'
        and filename ~= 'jacocoagent.jar' and vim.fn.filereadable(jar) == 1 then
        bundles[#bundles+1] = jar
      end
    end
  end
  return {
    cmd = {java, '-Declipse.application=org.eclipse.jdt.ls.core.id1',
      '-Dosgi.bundles.defaultStartLevel=4', '-Declipse.product=org.eclipse.jdt.ls.core.product',
      '-Dlog.protocol=true', '-Dlog.level=ALL', '-Xms' .. (vim.g.wordvim_java_xms or '256m'), '--add-modules=ALL-SYSTEM',
      '--add-opens', 'java.base/java.util=ALL-UNNAMED', '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
      '-jar', jars[1], '-configuration', config, '-data', workspace},
    root_dir = root,
    init_options = {bundles = bundles},
    settings = {java = {signatureHelp = {enabled=true}, contentProvider = {preferred='fernflower'}, format={enabled=true}}},
  }
end
return M
