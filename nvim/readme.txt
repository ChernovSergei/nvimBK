Word Vim integrated v6.58

v6.58: исправлено восстановление ручных разрывов страниц при открытии DOCX. Во временной копии для Pandoc реальный <w:br w:type="page"> теперь получает точный позиционный маркер; после завершения всех преобразований маркер удаляется, а разрыв привязывается к непосредственно следующему абзацу, включая пустой абзац, таблицу или повторяющийся заголовок. В исходный DOCX маркер не записывается.

v6.57: повреждённый или устаревший индекс модели таблицы больше не прерывает открытие всего DOCX. Для единственной модели и единственной таблицы индекс безопасно восстанавливается как 0; в неоднозначном случае некорректная запись пропускается, а реальная таблица импортируется обычным способом.

v6.56: исправлена ошибка сохранения v6.55 в Windows PowerShell: локальная переменная $pid конфликтовала со встроенной переменной $PID, доступной только для чтения. Переменная переименована в $propertyId; сохранение таблиц снова может завершить обработку docProps/custom.xml.

v6.55 TEST BUILD: модели таблиц хранятся в стандартном свойстве DOCX WordVimTables (docProps/custom.xml), а не в скрытом абзаце документа. При чтении метаданные восстанавливаются только во временной копии для Pandoc. Привязки разрывов страниц теперь загружаются после всех преобразований буфера, поэтому разрыв перед заголовком не теряет визуальную привязку после повторного открытия. Проверено на предоставленном WordVim_Test(2).docx: пакет открывается Pandoc, служебного текста в document.xml нет, page break, gridSpan, vMerge и заголовок после таблицы сохранены. Полный запуск PowerShell/Neovim в Windows требует проверки пользователем.

v6.54: Space w t открывает редактор таблицы. В редакторе ? или F1 открывают справку, q/Esc закрывают справку. Добавлено удаление полного соседнего HTML-представления объединённой таблицы при импорте. Проверен импорт HTML с rowspan/colspan; полный цикл объединения в Windows не проверен. Изменение цвета заголовка пока не исправлено; требуется отдельная диагностика.

v6.53: все команды редактора показаны несколькими строками по ширине окна. Позиция курсора учитывает высоту подсказок. W применяет таблицу к буферу и закрывает редактор; DOCX сохраняется отдельно через :w.

v6.52: редактор занимает рабочую область Neovim; hjkl/стрелки выбирают ячейки, w/b и Tab/Shift-Tab переходят между ячейками. Исправлены строка и байтовая колонка курсора. Enter изменяет содержимое выбранной ячейки.

v6.51: отделён блок метаданных от pipe-таблицы при экспорте в DOCX.
Импорт больше не ищет таблицу через последующие абзацы до конца документа.
Тесты: чтение присланного WordVim_Test.docx сохраняет Header; три цикла
Pandoc DOCX сохраняют одну таблицу, Header и следующий текст.
Ограничение: тесты модуля с заглушками Neovim API, не полный запуск Windows.

Изменение v6.44: добавлен отдельный плавающий редактор таблиц. В основном буфере таблица представлена одной строкой; создание и повторное редактирование выполняются командой :WordTable. Поддерживаются объединение ячеек, стили и границы отдельных ячеек, линии таблицы, шапка, строки и столбцы. Полная справка находится в WORDVIM_INTEGRATION_RU.txt и :WordHelp.

Изменение v6.45: текст всех ячеек отображается в основном буфере и доступен обычному поиску Vim. Строки таблицы защищены от прямого редактирования; :WordTable открывает редактор с любой строки таблицы.

Изменение v6.46: содержимое ячеек можно редактировать прямо в основном буфере, включая массовую замену :%s. Конструкция таблицы и её оформление остаются доступны только через :WordTable.

Исправление v6.47: исправлено появление символа | между буквами при преобразовании существующей таблицы в новый формат.

Исправление v6.48: исправлено открытие существующей таблицы в редакторе. Редактор больше не подменяет таблицу пустой сеткой 3 x 3 из-за смещённой привязки.

Исправление v6.49: устранено размножение таблицы после сохранения изменений во всплывающем редакторе.

v6.50: добавлена проверка конструкции таблиц перед сохранением DOCX. Этого оказалось недостаточно для сохранения текста при повторном открытии; см. v6.51.

Изменения v6.38:
- панели Styles стали уже по умолчанию (левая 4, правая 32) и регулируются командами `:WordStyleGutterWidth N` / `:WordStyleWidth N`;
- `Space w l` открывает/закрывает только левую колонку, `Space w r` только правую, `Space w s` обе;
- при `:q`, `:wq`, `:x` из DOCX вспомогательные панели Styles закрываются автоматически;
- underline в редакторе показывается компактно как `++text++`, а в DOCX сохраняется настоящим Word Underline style;
- Enter в конце пункта списка продолжает список на том же уровне; Enter на пустом пункте выходит из списка; `Space l x` явно снимает список с текущего пункта.

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

Word Vim v6.1 — Telescope image picker
--------------------------------------
Inside a DOCX buffer:
  Space i i
      Open Telescope and select an image from the current DOCX folder.
      With ripgrep installed, only supported image files are shown.

  :WordImagePicker
      Same picker from the current DOCX folder.

  :WordImagePicker C:\\Users\\Leo\\Pictures
      Start the picker in another folder.

  :WordImage C:\\path\\image.png
      Fallback direct insertion without Telescope.

After selection Word Vim asks for alt text and width. Width may be blank,
8cm, 120mm, 50%, etc. The image is inserted as a separate paragraph after
the current line. Existing WordImageWidth/Scale/Resize/Rotate/Reset commands
continue to work.

Word Vim v6.4 image caption workflow:
  Space+i+i -> select image in Neo-tree -> Width -> Add Figure caption?
  Yes uses the same real Word Figure caption engine as Space+c+f (SEQ Figure + bookmark + cross-reference support).
  No inserts only the image; caption can be added later with Space+c+f.

Word Vim v6.5 — image + caption round-trip fix
- DOCX reopen now recognizes Pandoc raw HTML <figure>/<figcaption> blocks.
- The editor again shows one compact Markdown image row plus the real Figure caption row.
- Figure SEQ/bookmark/cross-reference metadata is restored by the existing crossrefs.lua mechanism.
- Image paragraph and Caption paragraph styles are preserved as hidden Word styles.
- Word/Pandoc inch widths such as 3.14961in are normalized back to a friendly metric width (8cm) when exact.

Word Vim v6.13 paragraph-style engine
-------------------------------------
- Every real editor paragraph now has explicit style metadata, including Normal.
- Enter, o and O create a new Normal paragraph without stealing the style of the neighbouring paragraph.
- Empty Word paragraphs show their style number in the Style UI gutter.
- Style gutter refresh after insert-mode edits is deferred until textlock ends, preventing temporary gutter corruption/flicker.
- Shift+Enter remains a continuation of the same Word paragraph and does not create an independent style.

============================================================
Word Vim v6.15 — языки EN / RU / RO
============================================================

Переключение языка в DOCX:
  Space+l+e   English
  Space+l+r   Russian
  Space+l+o   Romanian

Команды:
  :WordLanguage en
  :WordLanguage ru
  :WordLanguage ro
  :WordLanguageEnglish
  :WordLanguageRussian
  :WordLanguageRomanian

Что меняется одновременно:
  1. язык проверки орфографии Neovim (spelllang);
  2. индикатор EN / RU / RO в statusline;
  3. раскладка текущего окна Windows Terminal (Windows);
  4. при сохранении — настоящий Word proofing language w:lang в DOCX.

При открытии DOCX Word Vim читает существующий w:lang и показывает
соответствующий EN/RU/RO. Открытие документа само по себе не переключает
раскладку Windows — она меняется только после явной команды Space+l+... .

Настройки (до require("wordvim").setup()):
  vim.g.wordvim_default_language = "en"          -- en / ru / ro
  vim.g.wordvim_switch_windows_layout = true     -- false отключает автопереключение Windows

Примечание v6.15:
  w:lang применяется ко всему документу. Смешанные языки по отдельным
  абзацам/фрагментам можно добавить отдельным следующим этапом.


WORD VIM v6.16 — АВТОПЕРЕКЛЮЧЕНИЕ РАСКЛАДКИ ПО РЕЖИМУ
=========================================================
Выбранный язык Word Vim (EN/RU/RO) теперь определяет раскладку только для Insert mode.

  Space+l+e   выбрать English для ввода
  Space+l+r   выбрать Russian для ввода
  Space+l+o   выбрать Romanian для ввода

Поведение:
  InsertEnter (i/a/o/O и т.п.) -> включается выбранный EN/RU/RO
  Esc / InsertLeave            -> автоматически включается English
  уход из DOCX                 -> автоматически включается English

Например: выбрали Space+l+r. В Normal mode остаётся ENG; нажали i — включился RUS;
нажали Esc — снова ENG. Выбранный RU запоминается для следующего входа в Insert mode.

Переключение сделано через user32 напрямую (быстро, без всплывающего PowerShell);
PowerShell используется только как резервный механизм, если FFI недоступен.


=== v6.18 ===
Глобальное переключение раскладки для всего Neovim: Normal mode = EN, Insert mode = выбранный EN/RU/RO. Выбор: Space+l+e / Space+l+r / Space+l+o. Язык DOCX w:lang отделен от системной раскладки.

v6.20
-----
- Исправлен E173 при запуске DOCX, когда Windows/команда запуска добавляла в argv
  лишний корень диска, например C:\\.
- При наличии DOCX Word Vim удаляет только отдельные аргументы вида C:\\ / D:\\.
- Обычные файлы и обычные каталоги не удаляются из argv.
