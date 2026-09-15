# v6.64

Java: support Mason share/jdtls/config and shared launcher, and Mason custom install_root_dir.
Keep legacy package paths and architecture selection. Startup failure notifications are
scheduled warnings, avoiding ERROR propagation through FileType into Neo-tree :edit.
Missing JDTLS: run :MasonInstall jdtls, wait for successful completion, restart Neovim.
Check :WordJavaStatus. This archive contains configuration, not the JDTLS installation.

Verified headless tests: shared and legacy layouts, custom Mason root, missing package,
file opening despite Java failure, mapping registration and attach. Actual user install
could not be read; a real JDTLS session was not verified.

Mason registry source: https://github.com/mason-org/mason-registry/blob/main/packages/jdtls/package.yaml
