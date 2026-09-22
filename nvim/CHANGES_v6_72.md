# v6.72
Java uses local syntax/Tree-sitter colors by default. Disable JDTLS semantic token
provider on attach to avoid stale ranges coloring fragments after edits. This is
a workaround for the screenshot symptom, not a confirmed server root-cause fix.
Diagnostics, navigation and completion remain enabled. Opt in again with
vim.g.wordvim_java_semantic_colors=true before Java attachment if desired.
Explicit Java keyword/punctuation palette removes inherited theme differences.
google-java-format now uses --aosp (four-space indentation). This is not the
IntelliJ formatter. Syntactically invalid Java may not format at all.
Tests checked capability handling, diagnostic preservation, mappings, colors and
formatter arguments. Actual user file and live JDTLS rendering were not available.
Install archive over configuration and fully restart Neovim.
