# Переименование в FitnessTracker

Приложение, виджеты, Watch, тексты RU/EN, разрешения, файлы экспорта и иллюстративные макеты используют **FitnessTracker**. Swift-пакет и тесты — `FitnessTrackerCore` / `FitnessTrackerCoreTests`. Главный проект — `FitnessTracker.xcodeproj`, схемы — **FitnessTracker Personal**, **FitnessTracker**, **FitnessTrackerWatch**, **FitnessTrackerWidgets**. Исходники находятся в `Sources/FitnessTrackerCore` и `Tests/FitnessTrackerCoreTests`.

## Обновление на Mac

```bash
git pull --ff-only
xcodegen generate
open FitnessTracker.xcodeproj
```

Закройте прежний проект и выберите схему **FitnessTracker Personal** для бесплатной Personal Team. Не открывайте только `Package.swift`: он собирает независимый Core. `Config/Local.xcconfig` сохраняется; скрипт установки его не перезаписывает.

Для обновления установленного приложения сохраните прежние **значения** Bundle ID, App Group, CloudKit container и Team. В `Config/Base.xcconfig` новые переменные `FITNESS_TRACKER_BUNDLE_ID`, `FITNESS_TRACKER_APP_GROUP`, `FITNESS_TRACKER_CLOUD_CONTAINER` поддерживают прежние переменные из существующего Local.xcconfig через aliases. Новый пример конфигурации использует новые имена. Простое изменение пользовательского имени приложения не требует новых Apple Developer resources.

Не удаляйте установленное приложение или store ради переименования. Первая сборка нового проекта и обновление поверх старой установки требуют проверки в Xcode.

## Совместимость

- Новые файлы — `.fitnesstracker` и `.json`, с `format: com.fitnesstracker.archive`, version 1.
- Прежние `.fitsession` и version-1 JSON с `format: com.fitsession.archive` продолжают импортироваться; decoder нормализует envelope, сохраняет workout/template UUID, даты и пользовательские строки. При новом экспорте используется текущий format ID. Поддержка старого ISO-8601 JSON одной тренировки сохранена.
- Основная схема ссылок — `fitnesstracker://`; старые `fitsession://` принимаются для тех же маршрутов.
- Имя SwiftData configuration, путь локального пульса, имя Watch archive, HealthKit sync prefix и widget kind сохранены в `AppCompatibility`. Они являются техническими ключами ранее установленных данных, не отображаемым названием продукта. Это защищает от создания пустого store, потери outbox/пульса, дублирования Health export и замены установленных виджетов.
- Код `StoredRecord` и JSON полей тренировки не изменён. Архивы не включают новые настройки/permissions или локальные измерения пульса.

Оставшиеся упоминания прежнего имени намеренно ограничены указанными ключами совместимости, их конфигурацией, тестами и этой инструкцией. В интерфейсе, названиях targets/modules и новых файлах используется FitnessTracker.

## Проверки

- **Implemented:** новое имя продукта, проекта, targets, схем, модуля Core, RU/EN, ресурсов и экспортов; поддержка прежних identities.
- **Linux-tested:** Core build и 78 tests, включая импорт старого envelope/новый экспорт; portable checks стабильных путей и обеих схем ссылок; validators конфигурации, signing aliases, ресурсов и branding; parser/lint Apple sources.
- **Requires Xcode validation:** генерация реального `.xcodeproj`, SDK type checking, signing, обновление существующего store, Watch/outbox, установленные widgets/Live Activities, открытие файлов из Files и внешний вид нового имени. Эти проверки не выполнялись на Linux.
- **Requires Apple Developer configuration:** сохраняйте существующие идентификаторы и Team для обновления; новых capabilities не добавлено. Для новой установки используйте собственные зарегистрированные identifiers как обычно.
