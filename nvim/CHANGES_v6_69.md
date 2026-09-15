# v6.69

Space gr / gr / Space ju restores Telescope search and preview for Java usages.
Enter opens the selected usage in a new tab through URI-safe LSP navigation.
Alt+Left / Alt+Right switch tabs. Implementation navigation is unchanged.
Ordinary comments remain gray; JavaDoc uses green, with an additional Java
Tree-sitter capture for /** documentation */ blocks. This is syntax coloring,
not IntelliJ Reader Mode rendering.

Validated picker configuration and Enter callback with mocked Telescope modules,
real Neovim URI buffer loading and tab creation, and highlight values.
Live Telescope UI/JDTLS and Java Tree-sitter rendering were not verified here.
