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
12) Postgresql
13) Maven

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

--Packages installation for html, js, css, react
npm install -g vscode-langservers-extracted --force
npm install -g stylelint --force
npm install -g stylelint --force

5) Java deletion/installation
--Deletion
apt remove openjdk-17-jdk openjdk-17-jre
apt purge openjdk-17-jdk openjdk-17-jre
apt autoremove

--Installation java 21 for Ubuntu Arm64
apt update
apt install openjdk-21-jdk
apt java --version

switch from previous java version to java 21 
sudo update-alternatives --config java 
sudo update-alternatives --config javac 

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
eval "$(ssh-agent -s)"
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
apt autoremove

-- Config files removal
apt purge neovim

-- Install Neovim
apt update
apt install -y neovim
neovim --version

if you strugle to install the latest neovim version, you need to download it first
cd /tmp 
curl -LO https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux64.tar.gz
wget https://github.com/neovim/neovim/releases/download/v1.10.4/nvim-linux-x86_64.tar.gz

than we unzip it 
tar xzf nvim-linux64.tar.gz

than we install install
sudo mv nvim-linux64 /opt/nvim

add into PATH
echo 'export PATH="/opt/nvim/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

--NVim configuratio
mkdir -p ~/.config/nvim
add next folders and file
-init.lua
-ftplugin
-lua
--core
--plugins

--NVim shortcuts & commands
:noh - deselect all search results
:nohlsearch - deselect all search results

8) Treesitter in lazy compatible with NVim 0.10.0
use {
	"nvim-treesitter/nvim-treesitter",
	tag = "v0.9.2",
	run = ":TSUpdate"
}

9) Mason
Press :Mason to enter into plugin manager
Select required plugin from the list and press "i"

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

--In PC Ubuntu
sudo apt install xclip
--add command in init.lua
vim.api.nvim_create_user_command('Copy', "w !xclip -selection clipboard", {})
after that you can select any text and implement command :Copy

12) Postgresql in Termux (not in Ubuntu)
a) Обновляем Termux и устанавливаем PostgreSQL
pkg update && pkg upgrade
pkg install Postgresql

TERMUX
b) Инициализация кластера (каталога данных)
initdb $PREFIX/var/lib/postgresql

$PREFIX → путь Termux (обычно /data/data/com.termux/files/usr)
Кластер создаёт базу postgres и шаблоны template0 и template1

c) Запуск и остановка сервера
# Запуск сервера
pg_ctl -D $PREFIX/var/lib/postgresql start

# Проверка статуса сервера
pg_ctl -D $PREFIX/var/lib/postgresql status

# Остановка сервера
pg_ctl -D $PREFIX/var/lib/postgresql stop

d) Опционально: добавляем alias для удобства

echo "alias pgstart='pg_ctl -D $PREFIX/var/lib/postgresql start'" >> ~/.bashrc
echo "alias pgstop='pg_ctl -D $PREFIX/var/lib/postgresql stop'" >> ~/.bashrc

UBUNTU
b) start stop restart
sudo systemctl start postgresql
sudo systemctl restart postgresql
sudo systemctl stop postgresql
sudo systemctl status postgresql

c) connect to a server
sudo -u postgresql psql #enter to a server under postgres user
psql -U postgres -d postgres # connect to a base postgres

d) default port
ss -ltnp | grep postgres	# 5432 by default 

e) Подключение к серверу

# Подключение к базе по имени
psql -U postgres -d postgres

# Подключение к другой базе
psql -U myuser -d springboot

COMMANDS
\q - exit

\dt - show tables for current schema (public by default)
\dt *.* - show tables for all schemas
\dt public.* - show tables for public schema

\l - show list of databases

\d users - show 'users' table structure
\d+ users - show 'users' table structure with additional information

STATUSES
postgres=# - common mode (ready to implement a new commands)
postgres-# - command wasn't completed. Press Ctrl+C to interrupt

f) Стандартные базы данных Postgresql

Имя
Назначение
postgres
системная база для работы
template0
шаблон для создания новых баз
template1
шаблон для создания новых баз

g) Создание и удаление базы данных
-- Создать базу
CREATE DATABASE springboot;

-- Создать базу с владельцем
CREATE DATABASE springboot OWNER postgres;

-- Удалить базу
DROP DATABASE springboot;

-- Удалить только если база существует
DROP DATABASE IF EXISTS springboot;

h) Создание и удаление таблиц

-- Создание таблицы
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Проверка таблиц
\d
\d users

-- Удаление таблицы
DROP TABLE users;

-- Без ошибки, если таблицы нет
DROP TABLE IF EXISTS users;

i) Создание пользователя и управление правами

-- Создать суперпользователя
createuser -s postgres

-- Создать пользователя с паролем
CREATE USER myuser WITH PASSWORD 'mypassword';

-- Дать права на базу
GRANT ALL PRIVILEGES ON DATABASE springboot TO myuser;

j) Работа с данными (CRUD)

-- Добавить данные
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com');

-- Прочитать данные
SELECT * FROM users;
SELECT name, email FROM users WHERE id=1;

-- Обновить данные
UPDATE users SET email='alice123@example.com' WHERE name='Alice';

-- Удалить данные
DELETE FROM users WHERE name='Bob';

k) Выполнение SQL-файла

# Запуск SQL файла
psql -U postgres -d postgres -f myscript.SQL

-f → указывает путь к SQL-файлу

l) Удаление PostgreSQL из Termux

# Остановить сервер
pg_ctl -D $PREFIX/var/lib/postgresql stop

# Удаляем пакеты
pkg uninstall postgresql

# Удаляем данные
rm -rf $PREFIX/var/lib/Postgresql

m) Советы по работе
Всегда указывай базу при подключении -d, иначе psql подключается к базе с именем пользователя Android (u0_a549)
Сервер в Termux работает локально на 127.0.0.1:5432
Для Spring Boot:

spring.datasource.url=jdbc:postgresql://127.0.0.1:5432/springboot
spring.datasource.username=myuser
spring.datasource.password=mypassword
spring.jpa.hibernate.ddl-auto=update

13) Maven
mvn spring-boot:run

there is no complete mvn debug function ready from the box.
it would be alias a function inside ~/.bashrc

alias mvn-debug-ns='mvn spring-boot:run -Dspring-boot.run.jvmArugments="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"'
