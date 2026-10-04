# AstraOS для OpenComputers

Небольшая автономная ОС-оболочка, запускаемая напрямую Lua BIOS и не использующая библиотеки OpenOS (`require`, `filesystem`, `io` в ядре). Проект предназначен для OpenComputers с Lua BIOS и файловой системой на загрузочном носителе.

## Что уже работает

- BIOS-загрузчик показывает логотип и в течение 2 секунд приглашает нажать `ENTER`, чтобы открыть меню загрузочных устройств; если клавишу не нажать, запускается устройство по умолчанию;
- в самом меню нет таймера autoboot: стрелки выбирают диск/RAID, `ENTER` загружает и сохраняет его как boot address в EEPROM, `ESC` возвращает загрузку по умолчанию;
- RAID в OpenComputers представлен одной файловой системой и отображается в этом же меню по метке и объёму;
- консоль на GPU + Screen, ввод с клавиатуры, история команд (стрелки вверх/вниз), backspace;
- базовые команды OpenOS: `ls`, `cd`, `pwd`, `cat`, `head`, `tail`, `grep`, `wc`, `find`, `tree`, `mkdir`, `rmdir`, `touch`, `rm`, `cp`, `mv`, `du`, `df`, `which`, `alias`, `unalias`, `history`, `man`, `echo`, `clear`, `lua`, `edit`, `sleep`, `wget`, `date`, `uptime`, `free`, `hostname`, `address`, `components`, `resolution`, `reboot`, `shutdown`;
- распространённые флаги: `ls -la`, `mkdir -p`, `cp -r`, `rm -r`/`rm -f`, `head -n N`, `tail -n N`, `grep -i`/`-n`/`-v`;
- `wget [-f] <URL> [файл]` скачивает HTTP(S) через Internet Card; старый файл перед заменой сохраняется до успешного переименования;
- пользовательские Lua-команды вида `/bin/<имя>.lua`;
- простое редактирование файла построчно (`.save` сохранить, `.cancel` отменить);
- инсталлятор для запуска из OpenOS: резервирует прежний `/init.lua` как `/init.lua.astraos-backup`.

Это **минимальная самостоятельная система**, а не полная совместимая копия OpenOS: команды реализуют основной повседневный набор, но не все опции и поведение OpenOS. Пока нет многозадачности, POSIX-прав, монтирования нескольких дисков (файловые команды работают на загрузочном диске), общего сетевого стека (из сетевых команд есть только `wget`), пакетного менеджера и полного набора OpenOS API. Используй Lua-скрипты и команды только из доверенных источников.

## Установка одной командой из OpenOS

Нужны запущенная OpenOS, интернет-карта в компьютере и разрешённый HTTP(S) в конфигурации OpenComputers. Вставь эту строку в терминал OpenOS:

```text
wget -f https://raw.githubusercontent.com/FoxFord1A/AstraOS-OpenComputers/main/install-online.lua /tmp/astraos-install.lua && lua /tmp/astraos-install.lua
```

Установщик скачает и проверит загрузчик с ядром, покажет список доступных для записи дисков и запросит номер нужного. Перед записью он попросит ввести `INSTALL`. Старые `/init.lua` и `/system/main.lua`, если они есть, будут сохранены как `/init.lua.astraos-backup` и `/system/main.lua.astraos-backup`. После установки выбери этот диск или RAID в EEPROM/BIOS как boot filesystem и перезагрузи компьютер; затем меню AstraOS позволит переключить источник и запомнит выбранный. Оператор `&&` поддерживается штатной командной оболочкой OpenOS.

## Ручная установка на загрузочный диск

1. Скопируй папку `astraos` на диск/флоппи, который доступен из работающей OpenOS.
2. В OpenOS перечисли файловые компоненты командой `components` или в Lua-коде через `component.list("filesystem", true)`.
3. Запусти инсталлятор, указав адрес нужного диска:

   ```text
   lua /путь/к/astraos/install.lua <адрес-filesystem>
   ```

   Например, если папка находится в `/home/astraos`, команда будет `lua /home/astraos/install.lua <адрес>`.
4. Установщик сохраняет старый `/init.lua` в `/init.lua.astraos-backup`, записывает новый загрузчик и ядро. Он **не меняет boot-адрес EEPROM автоматически**.
5. В BIOS/EEPROM выбери этот filesystem как загрузочный и перезагрузи компьютер.

Если запускаешь напрямую с подготовленного загрузочного носителя, на его корне должны лежать `init.lua` и каталог `system` с `main.lua`.

## Восстановление OpenOS

Загрузи OpenOS с другого носителя и восстанови резервные копии, если они есть: `/init.lua.astraos-backup` переименуй обратно в `/init.lua`, а `/system/main.lua.astraos-backup` — обратно в `/system/main.lua` на установленном диске. Если резервной копии не было, переустанови OpenOS на этот носитель.

## Структура

```text
init.lua            BIOS entry point
system/main.lua     ядро и интерактивная оболочка
install.lua         установщик для работающей OpenOS
install-online.lua  онлайн-установщик для OpenOS
```

## Совместимость и проверка

Код ориентирован на OpenComputers 1.7.x и Lua BIOS (архитектура Lua 5.2; синтаксис совместим и с Lua 5.3). Для запуска необходимы файловая система с правами записи, GPU, экран и клавиатура. Тестируй сначала на отдельной флоппи/диске: проект не эмулирует все особенности сборок модпака и сторонних BIOS.

Проверка синтаксиса и имитационный запуск на компьютере с Lua 5.2/5.3:

```sh
luac -p init.lua system/main.lua install.lua install-online.lua tests/*.lua
lua tests/smoke.lua .
lua tests/install_online.lua .
```

Smoke-тест подменяет OpenComputers-компоненты и проверяет BIOS-логотип, двухсекундную горячую клавишу, выбор RAID-файловой системы, сохранение boot address, запуск ядра и несколько команд оболочки. Отдельный тест имитирует скачивание и установку с сохранением резервных копий.

Документация и сверка совместимости: [Custom OSes](https://ocdoc.cil.li/tutorial:custom_oses), [Computer API](https://ocdoc.cil.li/api:computer), [Component API](https://ocdoc.cil.li/api:component), [Filesystem component](https://ocdoc.cil.li/component:filesystem), [описание RAID-блока](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/doc/en_US/block/raid.md), [GPU component](https://ocdoc.cil.li/component:gpu), [Internet component](https://ocdoc.cil.li/component:internet), [официальный каталог команд OpenOS](https://github.com/MightyPirates/OpenComputers/tree/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/bin), [OpenOS shell parser](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/sh.lua), [исходник OpenOS wget](https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/plan9k/bin/wget.lua).
