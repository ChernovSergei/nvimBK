# v6.67

Fix implementation navigation to JDTLS jdt:// virtual documents (JAR classes).
Create the split without a filename and pass the original Location/LocationLink
and client encoding to vim.lsp.util.show_document. URI characters never enter
an Ex command. Multiple results use vim.ui.select; cancel leaves windows unchanged.
Keys remain Space gi / gi. All prior appearance and help changes are included.

Verified real Neovim URI buffer loading via a test BufReadCmd handler, special
characters, new split, multiple results and cancel. Actual JDTLS decompilation
requires the user's running server and was not exercised by this test.
