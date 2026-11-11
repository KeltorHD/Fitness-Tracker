# FitLife: текущие идентификаторы

По явному требованию пользователя переход на FitLife выполняется **без обратной совместимости** с прежними названиями продукта, архивами и настройками.

Приложение, виджеты, Watch, RU/EN, разрешения, страницы входа, письма, документация и имена экспортов используют FitLife. Swift-пакет — `FitLifeCore`, тесты — `FitLifeCoreTests`. Xcode-проект — `FitLife.xcodeproj`, схемы — **FitLife Personal**, **FitLife**, **FitLifeWatch**, **FitLifeWidgets**. Серверное решение — `FitLife.Server.sln`, assemblies — `FitLife.Authentication`, `FitLife.Backend`, `FitLife.ServerLogging`, `FitLife.Server.Tests`.

## Контракты FitLife

- Архив: `.fitlife` / `.json`, `format: com.fitlife.archive`, строго версия **4**, MIME `application/vnd.fitlife+json`. Обязательны `format`, `version`, `exportedAt`, `workouts`, `templates`, `bodyWeights`. Прежние продуктовые форматы, версии 1–3 и одиночный Workout JSON без оболочки отклоняются.
- Ссылки приложения: только `fitlife://`. OAuth использует отдельный HTTPS callback либо явно настроенную reverse-DNS схему Personal Team.
- Xcode: только `FITLIFE_*`, без aliases прежних переменных. Значения по умолчанию: `com.example.fitlife`, `group.$(FITLIFE_BUNDLE_ID)`, `iCloud.$(FITLIFE_BUNDLE_ID)`.
- Локальная конфигурация SwiftData: `Workouts`; пульс: `FitLife/HeartRate`; Watch archive: `FitLife-watch.json`; HealthKit sync prefix: `FitLife.`; widget kind: `FitLife.Weekly`. Общие значения находятся в `Apple/Shared/AppIdentifiers.swift`.
- OAuth clients: `fitlife-ios`, `fitlife-ios-personal`, confidential Backend/JWT audience: `fitlife-api`; security-stamp claim: `fitlife:security_stamp`.
- Cookies: `__Host-FitLifeAuth`, `__Host-FitLifePasskey`; Data Protection application names: `FitLife.Authentication`, `FitLife.Backend`.
- PostgreSQL: раздельные БД и пользователи **authentication** / **backend**, без названия продукта. Параметры `AUTH_DB_NAME`, `AUTH_DB_USER`, `BACKEND_DB_NAME`, `BACKEND_DB_USER` задают текущую конфигурацию.
- Docker network: `fitlife-server`, label: `com.fitlife.project`.

Импорт CSV из стороннего FitSession остаётся самостоятельной функцией импорта, а не поддержкой прежнего собственного архива. UUID упражнений и лицензированные исходные данные библиотеки не меняются.

## Настройка и развёртывание

На Mac обновите существующий `Config/Local.xcconfig` по `Config/Local.xcconfig.example`, задайте текущие `FITLIFE_*`, Team и зарегистрированные Apple identifiers, затем выполните:

```bash
xcodegen generate
open FitLife.xcodeproj
```

Прежние конфигурационные переменные больше не читаются. Новые локальные identifiers открывают отдельные хранилища; автоматического переноса прежних данных, пульса, Watch outbox и виджетов нет. Предыдущие cookies, токены и Data Protection purposes не поддерживаются; нужен новый вход.

Для сервера подготовьте БД и пользователей `authentication` / `backend` и актуальную `.env` по [SERVER.md](SERVER.md). Изменение defaults не переименовывает существующие PostgreSQL-БД, пользователей, key rings или bind mounts. Репозиторные изменения не выполняют перенос, удаление или сброс рабочих данных. EF-миграции текущей схемы сохранены; обычный startup применяет их к настроенной БД.

Имя GitHub-репозитория и каталог checkout пока `Fitness-Tracker`; это отдельные имена инфраструктуры. Исторические скриншоты до переименования помечены в [описании превью](previews/README.md) и не включаются в app bundles.

## Проверки

`bash scripts/check-linux.sh` проверяет Core, portable behavior, новые идентификаторы и отказ для прежних схем/архивов, конфигурацию, ресурсы, локализации, синтаксис и форматирование. `bash scripts/check-server.sh` проверяет locked restore, сборку, unit/HTTP-тесты, formatting и серверные скрипты. PostgreSQL-категория запускается только с `FITLIFE_TEST_POSTGRES` к одноразовой БД.

Генерация реального Xcode-проекта, SDK type checking, signing, SwiftData, Watch, widgets/Live Activities и интерфейс требуют проверки на macOS/устройстве. Фактически выполненные проверки указываются в отчёте и [статусах](IMPLEMENTATION_STATUS.md).
