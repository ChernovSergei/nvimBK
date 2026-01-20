1) Install ubuntu terminal using proot-distro using termux 
2) Git installation
3) Neovim
4) Treesitter in lazy

1) Install ubuntu terminal using proot-distro using termux 
proot-distro install -y ubuntu
proot-distro login ubuntu

2) Git installation
apt update
apt install -y git
git --version

-- global config
git config --global user.name "Your name"
git config --global user.emal "your_email@example.com"
git config --global --list

-- generate SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"

-- start SSH
eval "$(ssh-agent -a)"
ssh-add ~/.ssh/id_ed25519

-- copy SSH key
cat ~/.ssh/id_ed25519

-- Open GitHub - Settings - SSH and GPG keys
-- Click New SSH key
-- Paste the key
-- save

-- Test GitHub connection
ssh -T git@github.com

-- expected
Hi username! You've successfully authenticated...

git init

-- create a repo on github without readme
-- copy SSH URL
git@github.com:username/my-project.git

git branch -M main
git remote add origin git@github.com:username/my-project.git
git push -u origin main

-- clone existing repository
git clone git@github.com:username/repo-name.git

3) Neovim
-- Removal
apt remove neovim

-- Config files removal
apt purge neovim

-- Minimal dev deps (safe list)
-- This covers: Tree-sitter; LSP; Java tooling; Neovim plugins
apt install -y\
	git\
	build-essential\
	gcc\
	make\
	nodejs\
	npm\
	python3

-- Install Neovim
apt update
apt install -y neovim
neovim --version

4) Treesitter in lazy
use {
	"nvim-treesitter/nvim-treesitter",
	tag = "v0.9.2",
	run = ":TSUpdate"
}

5) Console commands
-- copy one folder to another folder
cp -r source_folder destination_folder

-- copy a file to another folder
cp file_name.txt destination_folder

-- remove folder
rmdir folder_name

-- remove folder with content
rm -r folder_name
