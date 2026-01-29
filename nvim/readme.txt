1) F droid installation and termux/termux-app from it
2) Packages installation in termux
3) Install ubuntu terminal using proot-distro using termux 
4) Packages installation in ubuntu
5) Java installation
6) Git installation
7) Neovim
8) Treesitter in lazy
9) Mason
10) Console commands
11) Copy and paste from/to clipboard

2) Packages installation in termux
pkg update && pk upgrade -y
pkg install -y\
    proot-distro\
    git\
    neovim\
    openssh\
    wget\
    curl\
    -y termux-api

3) Install ubuntu terminal using proot-distro using termux 
proot-distro install -y ubuntu
proot-distro login ubuntu

4) Packages installation in ubuntu
aput update && apt upgrade -y
apt install -y\
    build-essential\
    gcc\
    make\
    git\
    curl\
    wget\
    unzip\
    npm\
    ca-certificates

--Node.js required for LSP, Treesitter, Mason
apt install -y nodejs 

--Python
apt install -y python3 python3-pip

5) Java deletion/installation
--Deletion
apt remove openjdk-17-jdk openjdk-17-jre
apt purge openjdk-17-jdk openjdk-17-jre
apt autoremove

--Installation java 21 for Ubuntu Arm64
apt update
apt install openjdk-21-jdk
apt java --version

--JAVA_HOME
readlink -f /usr/bin/java
--the answer usually - /usr/lib/jvm/java-21-openjdk-*

--add in ~/.bashrc
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-arm64
export PATH=$JAVA_HOME/bin:$PATH
source ~/.bashrc

--Maven installation
apt update
apt install maven -y
mvn -version

6) Git installation
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

-- rollback uncommited changes to the last commit
git restore .
git checkout -- .

7) Neovim v.0.10.0
-- Removal
apt remove neovim

-- Config files removal
apt purge neovim

-- Install Neovim
apt update
apt install -y neovim
neovim --version

--NVim configuratio
mkdir -p ~/.config/nvim
add next folders and file
-init.lua
-ftplugin
-lua
--core
--plugins

8) Treesitter in lazy compatible with NVim 0.10.0
use {
	"nvim-treesitter/nvim-treesitter",
	tag = "v0.9.2",
	run = ":TSUpdate"
}

9) Mason
install:
- jdtls
- lua_ls
- pyright
- ts_ls
- java-debug-adapter
- java-test

10) Console commands
-- copy one folder to another folder
cp -r source_folder destination_folder

-- copy a file to another folder
cp file_name.txt destination_folder

-- remove folder
rmdir folder_name

-- remove folder with content
rm -r folder_name

6) null-ls
-- for null-ls formater is required to be installed on linux
apt install google-java-format

11) Copy and paste from/to clipboard
--Install clipboard inside termux
pkg install termux-api

--Check:
termux-clipboard-get
termux-clipboard-set (Ctrl + D is exit)

--Go to ubuntu and Check
which termux-clipboard-get

--you should get copied text from termux
