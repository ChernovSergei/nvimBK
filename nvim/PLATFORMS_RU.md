# WordVim v6_62: Windows, Linux и Android proot-distro

Одна конфигурация выбирает окружение автоматически. На Android запускайте Neovim
внутри Linux-дистрибутива proot-distro. Для DOCX в Linux используется установленный
внутри этого же дистрибутива PowerShell 7 (pwsh) как помощник обработки ZIP/XML.
Рабочая оболочка терминала при этом остаётся bash/zsh/sh.

## Что изменено

- Windows: автоматически выбирается доступный PowerShell; Linux/proot: доступная
  пользовательская оболочка или bash/sh, без безусловной привязки к /bin/zsh.
- DOCX: все XML-операции вызывают общий обработчик: Windows PowerShell в Windows,
  pwsh в Linux/proot. Скрипты передаются файлом UTF-8, без ограничений длины
  командной строки и интерпретации текста документа оболочкой.
- Таблицы: снят пропуск сохранения границ, объединений и других свойств в Linux.
- Поворот изображений: Windows сохраняет System.Drawing; Linux/proot использует
  Python 3 + Pillow. Исходное изображение не перезаписывается.
- Java: учитывается ОС/ARM64, используются разные рабочие каталоги для проектов;
  начальная куча уменьшена до 256 МБ. Mason устанавливает jdtls, а запускает его
  только nvim-jdtls, без второго автоматического клиента.
- LSP не отключается по признаку Android. Java и Node.js работают через серверы,
  установленные в текущем окружении.
- Буфер обмена: используется системный провайдер Neovim; при доступном Termux:API
  в proot выбираются termux-clipboard-get/set. :Copy копирует весь текст буфера.
  Исправлено Ctrl+V в Visual mode: теперь оно берёт системный регистр +.
- Добавлена команда :WordHealth, показывающая найденные инструменты и провайдер.
- Исправлен импорт Shift+Enter из Pandoc: завершающий обратный слеш преобразуется
  в два пробела модели WordVim. Разрыв больше не превращается в отдельный абзац
  при повторном сохранении. Литералы с экранированным слешем и блоки кода сохранены.

## Зависимости

| Возможность | Windows | Linux / proot |
|---|---|---|
| Основа | Neovim 0.11+, Git | Neovim 0.11+, Git |
| DOCX, таблицы, стили | Pandoc + Windows PowerShell | Pandoc + PowerShell 7 (pwsh) |
| Поворот изображений | Windows PowerShell / System.Drawing | Python 3 + Pillow |
| Java | JDK 21+ для JDTLS; jdtls через Mason | То же; сборки JDK под архитектуру гостя |
| Node.js | Node.js LTS + npm | Node.js LTS + npm внутри гостя |
| Поиск и Tree-sitter | ripgrep, C-компилятор | ripgrep, C-компилятор |
| Системный буфер | Провайдер Neovim для Windows | wl-clipboard / xclip либо Termux:API |

Версия JDK запуска JDTLS не обязана совпадать с версией Java проекта.
PowerShell для Linux должен быть glibc-сборкой своей архитектуры. Основной сценарий
Android — Debian/Ubuntu ARM64 в proot-distro; установка Windows-версий инструментов
в такой гость не подходит. Для Alpine/musl и 32-битных гостей доступность всех
бинарных зависимостей отдельно не проверялась. Нативный Termux вне proot не является
целевым окружением DOCX-обработчика этой сборки.

## Установка конфигурации

1. Закройте Neovim и сохраните резервную копию текущей конфигурации.
2. Распакуйте содержимое архива в каталог конфигурации с init.lua:
   Windows — обычно %LOCALAPPDATA%/nvim;
   Linux и proot — обычно ~/.config/nvim (или каталог NVIM_APPNAME).
3. Установите зависимости в том окружении, где запускается Neovim.
4. Откройте Neovim, дождитесь установки плагинов/Mason и выполните :WordHealth.
5. Откройте проект Java/Node.js либо DOCX. Если jdtls только что установился,
   повторно откройте Java-файл. Для отладки/Java-тестов дополнительно нужны
   java-debug-adapter и java-test из Mason.

Каталоги плагинов/Mason между Windows и Linux не копируйте: пусть плагины и
бинарные инструменты устанавливаются отдельно под каждую ОС/архитектуру.
Общая палитра стилей сохраняется для всех документов внутри данной установки
Neovim; при необходимости её можно перенести отдельно из stdpath('state')/wordvim.

## Linux / Debian или Ubuntu в proot

Внутри гостя можно установить базовые инструменты через пакетный менеджер.
Например, для подходящей версии Debian/Ubuntu (в proot обычно от root):

    apt update
    apt install git curl unzip zip tar ripgrep build-essential python3 python3-pil pandoc nodejs npm

Для JDTLS установите JDK 21 или новее, например openjdk-21-jdk, если пакет есть
в репозитории дистрибутива. Для старого дистрибутива потребуется другой источник
JDK; версия java проверяется командой java -version.

Проверьте версию Neovim: пакет neovim из старого репозитория может быть старше
требуемой 0.11. Используйте подходящую сборку из официальных выпусков:
https://github.com/neovim/neovim/releases

PowerShell 7 устанавливается отдельно по инструкции Microsoft, в том числе
из Linux ARM64-архива. После установки pwsh должен находиться в PATH гостя:
https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux
https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-on-arm

Проверка без изменения системы:

    sh tools/check-linux.sh
    pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
    nvim

В Neovim выполните :WordHealth и :checkhealth.

## Android: доступ к внешнему буферу

В самом Termux (до входа в proot) установите пакет termux-api и совместимое
приложение Termux:API. Проверьте доступность termux-clipboard-get и
termux-clipboard-set из гостя. Если их нет в PATH/монтированиях гостя, исправьте
доступ к инструментам Termux; команда :WordHealth покажет отсутствие провайдера.
В терминале без провайдера остаётся вставка средствами самого терминала.
Для Wayland/X11 используются wl-clipboard/xclip; в proot без графической среды
эти программы сами по себе не обеспечат Android-буфер обмена.

Документация proot-distro: https://github.com/termux/proot-distro

## Сочетания и раскладка

F1 или :WordHelp — общая справка с оглавлением; Space w h — дополнительное
сочетание в Normal mode. Enter в оглавлении переходит к пункту, Backspace возвращает.
Ctrl+C в Visual mode копирует, Ctrl+V вставляет системный текстовый буфер.

Shift+Enter используется в Insert mode. Если терминал не передаёт Shift отдельно,
используйте Ctrl+g, затем Enter. :WordKeyCheck показывает полученный код клавиши.
:WordTerminalSetup относится только к Windows Terminal, в том числе WSL, и не
нужна для Termux. На Android физическая раскладка переключается средствами Android;
автоматическое переключение раскладки WordVim через user32 действует только в Windows.

## Проверки этой сборки

В среде Windows выполнены полные DOCX import/save/reopen через Windows PowerShell
и через PowerShell 7. После сохранения независимо проверен XML: таблица, изображение,
списки, Unicode, процентная ширина и настоящий w:br внутри одного Word-абзаца.
Проверены оба обработчика поворота изображения по пикселям и размерам.
Проверены выбор Linux/proot-инструментов и Termux-провайдера на имитации окружения,
ошибки зависимостей, длинные скрипты, Unicode, прежние тесты help и цветов.

Настоящий Linux/proot на Android в этой среде недоступен: WSL отказал в доступе.
Поэтому эта сборка содержит переносимую реализацию и инструкции, но полное
выполнение именно на вашем Android/дистрибутиве ещё нужно проверить через
:WordHealth и открытие/сохранение копии тестового DOCX.

Тесты из корня конфигурации:

    nvim --headless -n -u NONE -i NONE -l tests_platform.lua
    nvim --headless -n -u NONE -i NONE -l tests_docx_portable.lua
    nvim --headless -n -u NONE -i NONE -l tests_java_launch.lua

tests_docx_portable.lua требует Pandoc в PATH и соответствующий PowerShell;
создаёт только собственные файлы в work/. Чтобы проверить другой обработчик,
задайте переменную WORDVIM_TEST_POWERSHELL полным путём к pwsh.
