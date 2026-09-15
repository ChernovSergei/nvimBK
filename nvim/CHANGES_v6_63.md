# WordVim v6.63 — Java shortcuts

Java mappings are now registered before JDTLS starts, including when startup fails.
The Space leader is set before plugin loading. Java buffers also support K, gd,
gr, gD, Space rn, Space ca and Space d. Existing Space j* and Space tt/tn remain.
Use Normal mode and an English keyboard layout for these sequences.

:WordJavaStatus reports whether JDTLS is attached, or displays the startup error.
If JDTLS exits, LSP actions require fixing the server; bindings alone cannot replace it.
Standalone Java files use their parent directory when no project marker is found.

Install: close Neovim, extract the archive contents into your Neovim configuration
folder, replacing matching files (Windows: %LOCALAPPDATA%/nvim; Linux/proot:
~/.config/nvim). Keep your existing plugin data. Reopen a Java file.

Validation: headless Neovim tests passed for registration after startup failure,
server attachment, buffer isolation, standalone files, Java launch configuration,
and global help / DOCX editing regressions. An actual JDTLS connection on the user's
machine and Linux/Android terminal execution were not verified in this release.
