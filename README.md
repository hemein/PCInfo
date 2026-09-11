# PCInfo

Windows-приложение с графическим интерфейсом для получения информации о компьютерах в домене: имя ПК, версия ОС, процессор, оперативная память, диски, видеокарта и время работы без перезагрузки.

## Возможности

- Поиск компьютера по имени хоста или IP-адресу
- Сквозная авторизация: при запуске запрашиваются учётные данные доменной учётной записи
- Информация собирается через CIM/WMI (совместимо с Windows PowerShell 5.1 и PowerShell 7+)
- Значения полей можно выделять и копировать
- Оперативная память и диски выводятся построчно — по одному модулю/диску на строку

## Требования

- Windows с доступом к домену
- Учётная запись с правами на удалённый WMI/CIM-доступ к целевому компьютеру
- Учётная запись должна быть указана в одном из форматов:
  - `domain\username`
  - `username@domain.tld` (UPN)

## Установка и запуск

Готовый исполняемый файл доступен в разделе [Releases](https://github.com/hemein/PCInfo/releases) — скачайте `PCinfo.exe` и запустите.

Также можно запустить исходный скрипт напрямую:

```powershell
.\PCinfo.ps1
```

## Сборка exe

Исполняемый файл собирается из `PCinfo.ps1` с помощью модуля [ps2exe](https://github.com/MScholtes/PS2EXE):

```powershell
Install-Module ps2exe -Scope CurrentUser
Invoke-ps2exe -inputFile .\PCinfo.ps1 -outputFile .\PCinfo.exe -noConsole -STA -title "Информация о ПК" -product "PCInfo"
```

`PCinfo.exe` не хранится в репозитории (см. `.gitignore`) — актуальная сборка публикуется в [Releases](https://github.com/hemein/PCInfo/releases).

## Структура проекта

- `PCinfo.ps1` — исходный код приложения
- `PCinfo.exe` — скомпилированная версия (не в Git, публикуется в Releases)
- `CLAUDE.md` — внутренние инструкции для работы с проектом через Claude Code (не в Git)

## Версии

История изменений — в [Releases](https://github.com/hemein/PCInfo/releases) и в истории коммитов.
