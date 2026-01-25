local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	{ 'phaazon/hop.nvim' },
  	{
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons", -- optional, but recommended
	  "s1n7ax/nvim-window-picker",
    }
	},
	{
	  'nvim-treesitter/nvim-treesitter',
	  version = "v0.9.2",
	  build = ':TSUpdate',
	},
	{ 
		'neovim/nvim-lspconfig',
		version = "v2.5.0",
	},
	{
		"mason-org/mason.nvim",
		version = "1.*",
	},
	{
		"williamboman/mason-lspconfig.nvim",
		version = "1.*",
	},

	{
  		"mfussenegger/nvim-jdtls",
  		ft = { "java" },
	},
	{ 'joshdick/onedark.vim' },
    'hrsh7th/nvim-cmp',
    'hrsh7th/cmp-nvim-lsp',
    'hrsh7th/cmp-buffer',
    'hrsh7th/cmp-path',
    'hrsh7th/cmp-cmdline',
    'hrsh7th/vim-vsnip',
    'hrsh7th/cmp-vsnip',
    {
      "nvim-telescope/telescope.nvim",
      branch = "master",
      dependencies = { "nvim-lua/plenary.nvim" },
      config = function()
        require("telescope").setup({})
      end,
    },
    {
        "jose-elias-alvarez/null-ls.nvim",
        --dependencies = { "nvim-lua/plenary.nvim "},
    },
    { "mfussenegger/nvim-dap" },
    {
        "rcarriga/nvim-dap-ui",
        dependencies = { "mfussenegger/nvim-dap" },
    }
})
