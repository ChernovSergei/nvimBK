# Проверка переносимости v6.70 — 15 сентября 2026

Вывод: конфигурация рассчитана на Windows и Linux, но полная работоспособность
на всех трёх целевых средах не подтверждена. Android proot требует отдельной проверки.

Проверено запуском на Windows: Windows PowerShell и PowerShell 7 (UTF-8, длинные
скрипты, ошибки), DOCX import/save/reopen с проверкой XML таблицы, изображения,
списка и разрыва строки, справка, масштаб изображений и палитра. Выбор путей
Java для Windows/Linux/ARM и Linux/Termux-провайдеров проверен на имитации.
Полная установка всех плагинов с нуля и все Java/Node функции не проверены.
WSL недоступен: E_ACCESSDENIED; Android-устройство не подключено.

Исправление аудита: Tree-sitter ранее использовал несовместимые настройки API.
v6.70 выбирает master + configs.setup для Neovim 0.11, main + install/start для
0.12+. Выбор API проверен с подставными модулями, не сборкой всех парсеров.
После обновления: :Lazy sync, :TSUpdate, затем перезапуск Neovim.
Для main нужен tree-sitter-cli >=0.26.1, tar, curl, C-компилятор.
Для master следуйте его требованиям (CLI до 0.25.x). Не переносите parser/*.dll
и каталоги Mason с Windows в Linux; установите их заново в каждой среде.

Минимальные зависимости:
- Neovim 0.11+ и Git; версии плагинов, кроме отдельных веток/тегов, не закреплены
  единым lockfile, поэтому будущие обновления могут менять совместимость.
- Java: JDK, подходящий установленной версии JDTLS, Mason jdtls; Maven/Gradle
  либо wrapper для сборки проекта. Наличие клавиш тестов/отладки не подтверждает
  готовность DAP: java-test/java-debug-adapter и конфигурация адаптера нужны отдельно.
- Node.js: Node/npm, соответствующие LSP; Prettier для внешнего форматирования.
- DOCX: Pandoc и PowerShell (Windows) либо pwsh (Linux, включая proot).
- Linux поворот изображений: Python3 + Pillow.
- Поиск: ripgrep. Подсветка: компилятор и совместимый Tree-sitter CLI.

Для Android предпочтителен Debian/Ubuntu ARM64 (glibc) внутри proot.
Все зависимости, включая pwsh, устанавливаются внутри этого гостя под его
архитектуру. Нативный Termux, Alpine/musl и 32-bit этим аудитом не подтверждены.
Системный буфер на Linux требует рабочего Wayland/X11-провайдера, на Android —
доступных из гостя termux-clipboard-get/set и работающего Termux:API. Само наличие
команд ещё не подтверждает доступ к Android API. Шрифт задаёт приложение терминала.
Alt+стрелки, F1, Shift+Enter зависят от передачи клавиш терминалом. Запасные команды:
:tabnext / :tabprevious, :WordHelp; разрыв DOCX: Ctrl+g, затем Enter.

Проверка на каждой целевой машине:
1. :WordHealth и :checkhealth (включая Mason, Tree-sitter и clipboard).
2. Java: :WordJavaStatus, definition, Space gi, Space gr, форматирование и сборка.
3. Node: диагностика, переход к определению, форматирование, npm test проекта.
4. Копия DOCX: открыть, изменить таблицу/картинку, сохранить, открыть повторно.
5. Проверить внешний буфер, F1, Alt+стрелки, Shift+Enter.
Linux/proot дополнительно: sh tools/check-linux.sh.

Источники требований Tree-sitter:
https://github.com/nvim-treesitter/nvim-treesitter/blob/main/README.md
https://github.com/nvim-treesitter/nvim-treesitter/blob/master/README.md
Подробности установки остальных инструментов: PLATFORMS_RU.md.
