# FitSession: первая сборка на macOS

## 1. Инструменты

Установите **полный Xcode 26 или новее**, совместимый с вашей версией macOS, с iOS 26 и watchOS 26 SDK. Одних Command Line Tools недостаточно. Версию macOS выбирайте по [таблице совместимости Xcode](https://developer.apple.com/support/xcode/). Откройте Xcode, примите лицензию и установите iPhone/watchOS Simulator runtimes через Settings → Components.

При нескольких Xcode выберите нужный:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun swift --version
```

Установите [Homebrew](https://brew.sh), если его ещё нет, затем:

```bash
bash scripts/setup-macos.sh
```

Скрипт проверяет ОС и Xcode, устанавливает XcodeGen при необходимости, копирует `Config/Local.xcconfig.example` в `Config/Local.xcconfig`, запускает Core build/tests и `xcodegen generate`. Он не устанавливает Xcode, не открывает приложение и не меняет учётные записи или provisioning.

Ручной вариант:

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig  # только если файла ещё нет
swift build
swift test
xcodegen generate
open FitSession.xcodeproj
```

## 2. Идентификаторы и Signing

Заполните `Config/Local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOURTEAMID
FITSESSION_BUNDLE_ID = com.yourcompany.fitsession
```

App Group и CloudKit ID автоматически выводятся из Bundle ID:

| Назначение | Значение |
| --- | --- |
| iPhone | `com.yourcompany.fitsession` |
| Widget extension | `com.yourcompany.fitsession.widgets` |
| Watch | `com.yourcompany.fitsession.watchkitapp` |
| App Group | `group.com.yourcompany.fitsession` |
| CloudKit container | `iCloud.com.yourcompany.fitsession` |

Укажите свою Team во всех targets, включая unit/UI tests. Оставьте Automatically manage signing. Локальная конфигурация исключена из git; секреты и provisioning profiles не коммитьте.

В Signing & Capabilities проверьте:

| Target | Capability / настройка |
| --- | --- |
| FitSession | HealthKit; iCloud → CloudKit с вашим container; App Groups с вашей группой; Push Notifications; Background Modes → Remote notifications |
| FitSessionWidgets | Та же App Group |
| FitSessionWatch | Обычный signing, companion Bundle ID совпадает с iPhone. HealthKit и workout-processing здесь не нужны: это журнал подходов без фонового сбора датчиков |

Платные сервисы требуют соответствующего членства Apple Developer и ресурсов в портале. Simulator signing обычно не нужен, но включённые entitlements могут потребовать настроить Team или отдельные profiles перед запуском на устройстве. Не удаляйте реальные capability-файлы, чтобы скрыть ошибки provisioning.

`aps-environment` задаётся через `FITSESSION_APS_ENVIRONMENT`: Debug → development, Release → production; финальные значения проверьте в подписанном архиве. Live Activities обновляются локально, не требуют ActivityKit push token. Push capability используется для системной синхронизации CloudKit.

## 3. Генерация, Simulator и первая сборка

После изменения структуры исходников или `project.yml`:

```bash
xcodegen generate
open FitSession.xcodeproj
```

Выберите схему **FitSession**, затем iPhone Simulator с iOS 26+. Выполните Product → Build (`⌘B`), затем Run (`⌘R`). Схемы **FitSessionWatch** и **FitSessionWidgets** предусмотрены отдельно.

CLI после установки Simulator runtimes:

```bash
xcodebuild -list -project FitSession.xcodeproj
xcodebuild -showdestinations -project FitSession.xcodeproj -scheme FitSession
# Подставьте существующий Simulator UDID из предыдущего вывода:
xcodebuild -project FitSession.xcodeproj -scheme FitSession \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UDID' build
xcodebuild -project FitSession.xcodeproj -scheme FitSession \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UDID' test
```

Не используйте Linux `swift build` как свидетельство iOS-сборки. Первая реальная компиляция может потребовать корректировок Apple SDK; внесите их в исходники или `project.yml`, затем перегенерируйте проект. Сгенерированный `.xcodeproj` не является источником конфигурации.

Разбор частых ошибок:

- **Нет GlassEffectContainer / glass styles:** проверьте выбранный Xcode, SDK и deployment target 26.0. Не заменяйте эффект blur-реализацией.
- **Swift 6 isolation / Sendable:** проверьте границы `@MainActor` и `nonisolated` в делегатах. Передавайте `Data`, строки и Core value types через `Task`, а не `ModelContext`.
- **SwiftData macro / CloudKit schema:** проверьте defaults всех полей `StoredRecord`, отсутствие unique constraints, container ID и signed entitlements. Не стирайте хранилище как первый способ исправления.
- **Watch embedding/install:** проверьте companion ID и тип watchOS application. В XcodeGen зарегистрирована [проблема embedding для некоторых Xcode 26.x](https://github.com/yonaskolb/XcodeGen/issues/1613). Сначала обновите XcodeGen и сравните с watchOS target, созданным вашим Xcode; не применяйте слепую замену путей в pbxproj.
- **App Icon:** откройте оба catalogs, проверьте universal 1024×1024 для iOS/watchOS. При требованиях конкретной версии `actool` обновите Contents.json через редактор Asset Catalog и сохраните изменения.
- **StoreKit configuration:** откройте `Config/FitSession.storekit` в редакторе Xcode и дайте ему обновить формат, если требуется. Подтвердите выбор файла в Edit Scheme → Run → Options.

## 4. Визуальная проверка Liquid Glass

Полный список: [XCODE_VALIDATION.md](docs/XCODE_VALIDATION.md).

Проверьте светлую/тёмную тему, Increase Contrast, Reduce Transparency, Reduce Motion, VoiceOver, Dynamic Type, landscape и iPad. На активной тренировке выполните первый подход: кнопка завершения появляется в `GlassEffectContainer` с `glassEffectID` / `matchedGeometry`. Проверьте отсутствие наложений с клавиатурой и панелью действий. Для Reduce Motion приложение не инициирует собственную morph-анимацию. Системная прозрачность остаётся под управлением Apple.

## 5. Проверка интеграций на устройстве

1. **SwiftData:** начните тренировку, заполните подход, сверните/завершите процесс, запустите снова. Убедитесь, что выполненный подход и пауза сохранены. Завершите и найдите запись в истории.
2. **HealthKit:** откройте завершённую тренировку → Экспорт в «Здоровье». Проверьте разрешение/отказ, длительность и паузы, повторный экспорт с тем же sync identifier. Калории и пульс не выдумываются и не экспортируются. Удаление из истории не удаляет запись HealthKit.
3. **CloudKit:** сначала соберите с подписанными ресурсами. Включите синхронизацию в настройках, полностью перезапустите приложение. На двух устройствах с одним Apple ID проверьте создание, изменение и удаление записей, offline → online. Система выполняет eventual sync, проверка учётной записи не является индикатором завершения. Перед распространением инициализируйте development schema при необходимости через CloudKit Console и разверните её в production; debug-only schema initialization не включено в обычный запуск.
4. **Notifications:** включите уведомления, подтвердите разрешение, выполните подход и заблокируйте iPhone. Проверьте отмену уведомления при паузе, пропуске отдыха и завершении тренировки.
5. **Live Activity / Dynamic Island:** проверьте старт, подход, паузу, восстановление после перезапуска и завершение на поддерживающем устройстве. Поведение при выключенных Live Activities должно сохранять обычную тренировку.
6. **Widget:** включите передачу сводки, добавьте виджет, завершите тренировку. Проверьте недельную цель, смену недели, отключение передачи и скрытие чувствительных данных.
7. **Watch:** установите приложение на paired Watch. Запишите несколько подходов офлайн, перезапустите Watch app, завершите. После соединения проверьте запись на iPhone и уменьшение очереди Watch только после подтверждения сохранения. Повторная передача не создаёт дубликат. Watch не зеркалирует текущую iPhone-сессию и не собирает пульс; он ведёт отдельную тренировку «Всё тело A».
8. **StoreKit 2:** тестовый файл содержит Non-Consumable `com.example.fitsession.pro.lifetime`. Проверьте покупку, отмену, pending, restore, revoke и переход графика 8 → 26 недель. Для App Store Connect зарегистрируйте свой продукт, замените ID в `PurchaseStore.swift` и `.storekit`; в схеме выберите None для локального StoreKit-файла при проверке Sandbox/TestFlight.

## 6. Перед публикацией

Пройдите unit/UI tests и сценарии выше, исправьте все ошибки первой компиляции, обновите [IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) и фактические результаты проверок. Подготовьте privacy policy URL, App Privacy ответы для выбранной конфигурации iCloud/HealthKit, store listing, иконки/скриншоты и production CloudKit schema. Privacy manifest в репозитории описывает отсутствие tracking/аналитики и причины использования UserDefaults; его следует сверить с итоговым архивом и фактической обработкой данных.

Репозиторий не был собран или опубликован через Xcode в Linux-сессии.
