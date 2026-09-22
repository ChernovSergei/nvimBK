# v6.71 — startup regression fix

v6.70 selected the Tree-sitter API using the Neovim version alone. An installed
older plugin checkout has no install function, aborting init.lua before LSP/help.
v6.71 checks actual exported functions. On Neovim 0.12 with the old checkout,
it uses available native parsers and schedules an actionable warning instead of
running unsupported legacy setup. Installation/setup errors no longer abort init.

After replacing configuration: :Lazy sync, restart Neovim, then :TSUpdate.
The tbl_flatten deprecation warning is separate; this fix does not suppress it.
Tests cover matching/mismatched APIs, installer failure and help/DOCX regressions.
Real plugin update on the user's machine remains to be performed there.
