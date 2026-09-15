# v6.66

Java Normal mode: Space gi or gi opens implementation in a vertical split.
Multiple implementations: select a result and press Enter to open a vertical split.
Space gr, gr, Space ju: usages picker (declarations excluded), including a single result.
In usages: Enter opens result; Ctrl+v opens in a vertical split. Ctrl+w w switches windows.
Requires an attached JDTLS server.
Java tab labels: last directory / filename, e.g. model/UnderLineStyle.java.
Other files: filename. A + means unsaved changes anywhere in the tab.
Help updated. Navigation options and tab rendering checked in headless Neovim;
actual JDTLS navigation was not available for an end-to-end test.
