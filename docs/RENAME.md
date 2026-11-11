# Переименование в FitLife

Приложение, виджеты, Watch, тексты RU/EN, разрешения, имена файлов экспорта, страницы входа и письма используют **FitLife**. Swift-пакет и тесты — `FitLifeCore` / `FitLifeCoreTests`, исходники — `Sources/FitLifeCore` и `Tests/FitLifeCoreTests`. Главный проект — `FitLife.xcodeproj`, схемы — **FitLife Personal**, **FitLife**, **FitLifeWatch**, **FitLifeWidgets**.

Серверное решение — `FitLife.Server.sln`, проекты и assemblies — `FitLife.Authentication`, `FitLife.Backend`, `FitLife.ServerLogging`, `FitLife.Server.Tests`. Dockerfile, project references, package lock files и команды проверок используют новые имена. В EF Core обновлены только ссылки на пространства имён; IDs миграций, схема БД и операции миграций сохранены.

## Обновление на Mac

```bash
git pull --ff-only
xcodegen generate
open FitLife.xcodeproj
```

Закройте прежний проект и выберите схему **FitLife Personal** для бесплатной Personal Team. Не открывайте только `Package.swift`: он собирает независимый Core. `Config/Local.xcconfig` сохраняется; скрипт установки его не перезаписывает.

Для обновления установленного приложения сохраните прежние **значения** Bundle ID, App Group, CloudKit container и Team. Переменные `FITNESS_TRACKER_*` и aliases `FITSESSION_*` в `Config/Base.xcconfig` остаются совместимыми с существующим Local.xcconfig. Их технические имена не определяют отображаемое название приложения. Простое изменение имени продукта не требует новых Apple Developer resources.

Не удаляйте установленное приложение или store ради переименования. Первая сборка нового проекта и обновление поверх старой установки требуют проверки в Xcode.

## Совместимость

- Имена новых экспортов начинаются с `FitLife`; расширения `.fitnesstracker` / `.json`, `format: com.fitnesstracker.archive`, MIME type и текущая версия 4 сохранены. Переименование не меняет wire format: файлы доступны прежним клиентам и Backend.
- Прежние `.fitsession`, архивы версий 1–4 с `com.fitnesstracker.archive` / `com.fitsession.archive` и старый ISO-8601 JSON одной тренировки продолжают импортироваться. Миграции содержимого и сохранение workout/template UUID, дат и пользовательских строк не изменены.
- Основная схема ссылок — `fitlife://`; `fitnesstracker://` и `fitsession://` принимаются для тех же маршрутов. Это не меняет отдельную настроенную OAuth callback scheme.
- Имя SwiftData configuration, путь локального пульса, имя Watch archive, HealthKit sync prefix и widget kind сохранены в `AppCompatibility`. Это защищает от создания пустого store, потери outbox/пульса, дублирования Health export и замены установленных виджетов. Строки для стабильных UUID CSV-импорта также сохранены.
- Код `StoredRecord` и JSON полей тренировки не изменён. Архивы не включают настройки/permissions или локальные измерения пульса.
- На сервере сохранены OAuth client IDs, JWT audience и security-stamp claim, имена cookies `__Host-FitnessTrackerAuth` / `__Host-FitnessTrackerPasskey`, Data Protection application names `FitnessTracker.Authentication` / `FitnessTracker.Backend`, имена БД/пользователей и Docker network. Существующие `.env`, bind mounts, сертификаты, ключи, аккаунты и сессии не требуют переноса ради названия.
- Каталог checkout и адрес Git remote не определяют имя продукта; их переименование не требуется для сборки FitLife.

Прежние имена остаются в перечисленных технических идентификаторах, их конфигурации, тестах и этой инструкции. В интерфейсе, названиях targets/modules/assemblies используется FitLife.

## Проверки

- **Реализовано:** новое имя продукта, проекта, targets, схем, модуля Core, серверных проектов, RU/EN, ресурсов, страниц входа, писем и имён экспортов; поддержка прежних identities.
- **Проверки на Linux:** `bash scripts/check-linux.sh` проверяет Core, portable behavior, стабильные пути и текущую/прежние схемы ссылок, конфигурацию, signing aliases, ресурсы, брендинг, синтаксис и форматирование Apple sources. `bash scripts/check-server.sh` выполняет locked restore, сборку, серверные тесты и проверку форматирования. Фактически выполненные проверки указываются в отчёте к изменению; эти команды не подтверждают работу Apple SDK.
- **Требует Xcode:** генерация реального `.xcodeproj`, SDK type checking, signing, обновление существующего store, Watch/outbox, установленные widgets/Live Activities, открытие файлов из Files и внешний вид нового имени. На Linux эти проверки недоступны.
- **Apple Developer configuration:** сохраняйте существующие идентификаторы и Team для обновления; новых capabilities не добавлено. Для новой установки используйте собственные зарегистрированные identifiers как обычно.
