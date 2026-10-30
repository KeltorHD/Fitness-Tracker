# FitnessTracker: первая сборка на macOS

После переименования закройте прежний проект, выполните `git pull --ff-only` и `xcodegen generate`, затем откройте **FitnessTracker.xcodeproj**. Выберите **FitnessTracker Personal**. Сохраняйте значения Team, Bundle ID, App Group и CloudKit из существующего `Config/Local.xcconfig`: прежние переменные поддержаны aliases. Не удаляйте приложение/store. [Правила обновления](docs/RENAME.md).

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
open FitnessTracker.xcodeproj
```

## 2. Идентификаторы и Signing

Для **бесплатной Personal Team** используйте схему **FitnessTracker Personal**. Она выбирает PersonalDebug/PersonalRelease и Config/PersonalTeam.entitlements без iCloud и Push Notifications. История сохраняется в локальной SwiftData; JSON/.fitnesstracker, Liquid Glass, HealthKit, локальные уведомления, Live Activity/Dynamic Island, WidgetKit/App Groups и Watch сохраняются. Доступность HealthKit и App Groups для бесплатного Apple Developer account указана в [таблице Apple](https://developer.apple.com/help/account/reference/supported-capabilities-ios); фактический provisioning следует проверить на устройстве.

Схема **FitnessTracker** сохраняет полный набор capabilities и требует подходящей команды Apple Developer Program для iCloud/Push. Это различие конфигураций сборки, платных функций внутри приложения нет.

Если Xcode сообщает `Personal development teams ... do not support Push Notifications and iCloud`:

1. Обновите репозиторий и выполните `xcodegen generate` в его корне, затем `open FitnessTracker.xcodeproj`.
2. Выберите **FitnessTracker Personal → ваш iPhone**.
3. Укажите Personal Team для FitnessTracker, FitnessTrackerWidgets и FitnessTrackerWatch в Signing & Capabilities с Automatically manage signing.
4. Замените `com.yourcompany.fitnesstracker` в Config/Local.xcconfig на свой уникальный FITNESS_TRACKER_BUNDLE_ID, например `com.alexanderproshchenkov.fitnesstracker`. App Group и IDs вложенных targets выводятся из него автоматически. Для сохранения Team после следующей генерации внесите реальный Team ID в DEVELOPMENT_TEAM локального файла.
5. Нажмите ⌘R. Не удаляйте capabilities из Config/App.entitlements: они используются полной схемой.

Заполните `Config/Local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOURTEAMID
FITNESS_TRACKER_BUNDLE_ID = com.yourcompany.fitnesstracker
```

App Group и CloudKit ID автоматически выводятся из Bundle ID:

| Назначение | Значение |
| --- | --- |
| iPhone | `com.yourcompany.fitnesstracker` |
| Widget extension | `com.yourcompany.fitnesstracker.widgets` |
| Watch | `com.yourcompany.fitnesstracker.watchkitapp` |
| App Group | `group.com.yourcompany.fitnesstracker` |
| CloudKit container | `iCloud.com.yourcompany.fitnesstracker` |

Укажите свою Team во всех targets, включая unit/UI tests. Оставьте Automatically manage signing. Локальная конфигурация исключена из git; секреты и provisioning profiles не коммитьте.

В Signing & Capabilities проверьте:

| Target | Capability / настройка |
| --- | --- |
| FitnessTracker | HealthKit; iCloud → CloudKit с вашим container; App Groups с вашей группой; Push Notifications; Background Modes → Remote notifications |
| FitnessTrackerWidgets | Та же App Group |
| FitnessTrackerWatch | Обычный signing, companion Bundle ID совпадает с iPhone. HealthKit и workout-processing здесь не нужны: это журнал подходов без фонового сбора датчиков |

Платные сервисы требуют соответствующего членства Apple Developer и ресурсов в портале. Simulator signing обычно не нужен, но включённые entitlements могут потребовать настроить Team или отдельные profiles перед запуском на устройстве. Не удаляйте реальные capability-файлы, чтобы скрыть ошибки provisioning.

`aps-environment` задаётся через `FITNESS_TRACKER_APS_ENVIRONMENT`: Debug → development, Release → production; финальные значения проверьте в подписанном архиве. Live Activities обновляются локально, не требуют ActivityKit push token. Push capability используется для системной синхронизации CloudKit.

## 3. Генерация, Simulator и первая сборка

После изменения структуры исходников или `project.yml`:

```bash
xcodegen generate
open FitnessTracker.xcodeproj
```

Выберите схему **FitnessTracker Personal** для Personal Team либо **FitnessTracker** для полной конфигурации, затем iPhone Simulator с iOS 26+ или свой iPhone. Выполните Product → Build (`⌘B`), затем Run (`⌘R`). Схемы **FitnessTrackerWatch** и **FitnessTrackerWidgets** предусмотрены отдельно.

CLI после установки Simulator runtimes:

```bash
xcodebuild -list -project FitnessTracker.xcodeproj
xcodebuild -showdestinations -project FitnessTracker.xcodeproj -scheme FitnessTracker
# Подставьте существующий Simulator UDID из предыдущего вывода:
xcodebuild -project FitnessTracker.xcodeproj -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UDID' build
xcodebuild -project FitnessTracker.xcodeproj -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UDID' test
```

Не используйте Linux `swift build` как свидетельство iOS-сборки. Первая реальная компиляция может потребовать корректировок Apple SDK; внесите их в исходники или `project.yml`, затем перегенерируйте проект. Сгенерированный `.xcodeproj` не является источником конфигурации.

Разбор частых ошибок:

- **`unable to type-check this expression in reasonable time` в ExerciseProgressTests:** обновите исходники через `git pull --ff-only` и повторите `swift test`. Извлечение optional, расчёт ожидаемого 1ПМ и проверка разницы теперь разделены на типизированные `Double`-выражения; допуск теста не изменён. В ExerciseLibraryTests вложенный `#require` также вынесен перед JSON encoding. Если ошибка возникла в `setup-macos.sh`, после успешных тестов повторите скрипт: при сбое `swift test` он останавливается до генерации проекта.
- **Нет GlassEffectContainer / glass styles:** проверьте выбранный Xcode, SDK и deployment target 26.0. Не заменяйте эффект blur-реализацией.
- **Swift 6 isolation / Sendable:** проверьте границы `@MainActor` и `nonisolated` в делегатах. Передавайте `Data`, строки и Core value types через `Task`, а не `ModelContext`.
- **SwiftData macro / CloudKit schema:** проверьте defaults всех полей `StoredRecord`, отсутствие unique constraints, container ID и signed entitlements. Не стирайте хранилище как первый способ исправления.
- **Watch embedding/install:** проверьте companion ID и тип watchOS application. В XcodeGen зарегистрирована [проблема embedding для некоторых Xcode 26.x](https://github.com/yonaskolb/XcodeGen/issues/1613). Сначала обновите XcodeGen и сравните с watchOS target, созданным вашим Xcode; не применяйте слепую замену путей в pbxproj.
- **App Icon:** откройте оба catalogs, проверьте universal 1024×1024 для iOS/watchOS. При требованиях конкретной версии `actool` обновите Contents.json через редактор Asset Catalog и сохраните изменения.

## 4. Визуальная проверка Liquid Glass

Полный список: [XCODE_VALIDATION.md](docs/XCODE_VALIDATION.md).

Проверьте светлую/тёмную тему, Increase Contrast, Reduce Transparency, Reduce Motion, VoiceOver, Dynamic Type, landscape и iPad. На активной тренировке выполните первый подход: кнопка завершения появляется в `GlassEffectContainer` с `glassEffectID` / `matchedGeometry`. Проверьте отсутствие наложений с клавиатурой и панелью действий. Для Reduce Motion приложение не инициирует собственную morph-анимацию. Системная прозрачность остаётся под управлением Apple.

## 5. Проверка интеграций на устройстве

1. **SwiftData:** начните тренировку, заполните подход, сверните/завершите процесс, запустите снова. Убедитесь, что выполненный подход и пауза сохранены. Завершите и найдите запись в истории.
2. **HealthKit:** откройте завершённую тренировку → Экспорт в «Здоровье». Проверьте разрешение/отказ, длительность и паузы, повторный экспорт с тем же sync identifier. Калории и пульс не выдумываются и не экспортируются. Удаление из истории не удаляет запись HealthKit.
3. **CloudKit:** сначала соберите с подписанными ресурсами. Включите синхронизацию в настройках, полностью перезапустите приложение. На двух устройствах с одним Apple ID проверьте создание, изменение и удаление записей, offline → online. Система выполняет eventual sync, проверка учётной записи не является индикатором завершения. Перед распространением инициализируйте development schema при необходимости через CloudKit Console и разверните её в production; debug-only schema initialization не включено в обычный запуск.
4. **Notifications:** включите уведомления, подтвердите разрешение, выполните подход и заблокируйте iPhone. Проверьте отмену уведомления при паузе, пропуске отдыха и завершении тренировки.
5. **Live Activity / Dynamic Island:** проверьте старт, подход, активное время и отдых после блокировки, pause/resume/skip-rest кнопки, cold-launch intent, переход по UUID, восстановление после перезапуска и завершение на поддерживающем устройстве. После изменений обязательно перегенерируйте project: shared intents собираются в main app с FITNESS_TRACKER_APP и в widget extension без этого флага. Поведение при выключенных Live Activities должно сохранять обычную тренировку.
6. **Widget:** включите передачу сводки, добавьте виджет, завершите тренировку. Проверьте недельную цель, смену недели, отключение передачи и скрытие чувствительных данных.
7. **Watch:** установите приложение на paired Watch. Запишите несколько подходов офлайн, перезапустите Watch app, завершите. После соединения проверьте запись на iPhone и уменьшение очереди Watch только после подтверждения сохранения. Повторная передача не создаёт дубликат. Watch не зеркалирует текущую iPhone-сессию и не собирает пульс; он ведёт отдельную тренировку «Всё тело A».

## 6. Перед публикацией

Пройдите unit/UI tests и сценарии выше, исправьте все ошибки первой компиляции, обновите [IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) и фактические результаты проверок. Подготовьте privacy policy URL, App Privacy ответы для выбранной конфигурации iCloud/HealthKit, store listing, иконки/скриншоты и production CloudKit schema. Privacy manifest в репозитории описывает отсутствие tracking/аналитики и причины использования UserDefaults; его следует сверить с итоговым архивом и фактической обработкой данных.

Репозиторий не был собран или опубликован через Xcode в Linux-сессии.

Описание фонового поведения: [BACKGROUND_AND_DYNAMIC_ISLAND.md](docs/BACKGROUND_AND_DYNAMIC_ISLAND.md).

## Локальная библиотека и фотографии

После `xcodegen generate` убедитесь, что `ExerciseMedia` копируется как folder reference в главный target, а `ExerciseLibrary.ru.json` и `ExerciseLibrary.en.json` включены в SPM resource bundle. Проверьте первый запуск в авиарежиме: каталог, инструкции RU/EN и обе фотографии должны работать без сети. Сценарии: [EXERCISE_LIBRARY.md](docs/EXERCISE_LIBRARY.md). PNG/SVG в `docs/previews` — макеты, не скриншоты запуска.

## Локализация RU/EN

После обновления исходников снова выполните `xcodegen generate`: String Catalogs должны быть в Resources приложения, виджетов и Watch. Xcode компилирует `.xcstrings` в языковые bundles; Linux-проверка проверяет только входные каталоги.

В приложении откройте **Настройки → Основные → Язык приложения**. Проверьте переключение без перезапуска и после повторного запуска; «Как на устройстве» учитывает приоритет языков iOS. Запустите L10nTests, WidgetSnapshotTests и UI-тест переключения языка. Проверьте обе локали в каталоге, истории, файловых диалогах, уведомлениях, виджете и Dynamic Island; Watch использует свой системный язык. Разрешения HealthKit и системные подписи App Intents следуют системному/назначенному в iOS языку приложения. Полные сценарии: [LOCALIZATION.md](docs/LOCALIZATION.md), [XCODE_VALIDATION.md](docs/XCODE_VALIDATION.md).

## Импорт и экспорт файлов

После установки приложения проверьте **Настройки → Данные → Импорт и экспорт**: сохранить архив в `.json` и `.fitnesstracker`, открыть его из «Файлов», подтвердить preview и повторить импорт без дублей. Проверьте export одной тренировки из меню карточки, iCloud Drive, cold launch и передачу через Share/AirDrop. Регистрация UTI находится в App-Info.plist; дополнительных entitlements для этих диалогов не требуется. Код рассчитан на iOS 26, без document APIs iOS 27. Правила формата и ограничения: [IMPORT_EXPORT.md](docs/IMPORT_EXPORT.md), сценарии: [XCODE_VALIDATION.md](docs/XCODE_VALIDATION.md).

## Mi Band / два режима трекера

После `git pull --ff-only` снова выполните `xcodegen generate`: добавлены Swift-файлы сервисов, экранов и Bluetooth purpose string. Запустите схему **FitnessTracker Personal** на физическом iPhone. В «Настройки → Основные → Трекер» проверьте Apple «Здоровье» после синхронизации Mi Fitness; для Bluetooth сначала начните тренировку и включите **Share HR** на браслете, затем найдите пульсометр в FitnessTracker. Права HealthKit и Bluetooth выдаются отдельно по действию пользователя. Проверьте блокировку, паузу, потерю связи и график после завершения. Сборка и соединение с Mi Band на Linux не проверялись. Полная инструкция: [MI_BAND.md](docs/MI_BAND.md), checklist: [XCODE_VALIDATION.md](docs/XCODE_VALIDATION.md).

Для **HUAWEI WATCH GT 6 Pro** в этом же разделе выберите **Модель трекера → HUAWEI WATCH GT 6 Pro**. Для истории сначала проверьте HUAWEI Health → Apple «Здоровье»; для пульса включите **HR Data Broadcasts** на часах и запустите поиск в FitnessTracker. Отсутствие этого пункта и набор передаваемых показателей зависят от прошивки/региона. Реальное соединение с GT 6 Pro не проверялось на Linux. Полные шаги и ссылки производителя — в [MI_BAND.md](docs/MI_BAND.md).

## Демонстрационные тренировки

После обновления выполните `xcodegen generate`, чтобы включить новый `DemoDataSection.swift` в главный target. Запустите приложение и откройте **Настройки → Демонстрационные данные → Открыть демо-профиль**. Подтвердите загрузку: в дневнике должны появиться 24 тренировки, в каталоге — три демо-плана, на экранах — баннер вымышленных данных. Проверьте перезагрузку набора и **Вернуться к моим данным**; личные записи должны оставаться прежними. При активной личной тренировке вход недоступен.

Запустите новые сценарии в `AppStoreTests` и `FitnessTrackerUITests`. Проверьте, что демо не экспортируется в «Здоровье», не пишет пульс и не заменяет сводку виджета. Эти Apple-тесты и реальный интерфейс на Linux не проверены. [Поведение демо-профиля](docs/DEMO_DATA.md), [полный checklist](docs/XCODE_VALIDATION.md).

## Графики по упражнениям

После обновления снова выполните `xcodegen generate`: добавлены `ExerciseProgressView.swift` и `ExerciseProgressViewModel.swift`. В **Результаты → Прогресс по упражнениям** проверьте пять показателей, выбор упражнения и периода, а также выбор точки на графике. Для просмотра истории конкретного упражнения откройте **Прогресс упражнения** в активной или завершённой тренировке. В последнем случае должна выделяться её точка; текущая незавершённая сессия не учитывается.

Для заполненного примера используйте демо-профиль. Запустите обновлённые PresentationModelTests и три новых UI-сценария графиков. Проверьте кг/фунты, RU/EN, VoiceOver, один отсчёт, bodyweight, отсутствие подходящего 1ПМ и навигацию назад без изменения тренировки. Linux выполнил Core и Foundation-проверки, но не компилировал SwiftUI/Charts с Apple SDK. [Правила и формулы](docs/EXERCISE_PROGRESS.md), [сценарии](docs/XCODE_VALIDATION.md).

## Календарь результатов и фиксация веса

Обновите репозиторий и выполните `xcodegen generate`: добавлены BodyWeightCard/Editor/HistoryView/ViewModel и адаптивный asset ResultsSurface. На «Результатах» проверьте крупные круглые даты календаря без многоточий, меню «История → …», нейтральные карточки и контурные tabs. Сравните с предоставленным образцом на том же iPhone; Linux не проверяет фактическую геометрию SwiftUI.

В **Результаты → Весы → Записать** сохраните вес и проверьте историю/изменение, затем укажите вес в активной и завершённой тренировке. После завершения её значение должно появиться в общей истории, повтор тренировки начинается без веса. Проверьте точку/запятую, кг/фунты, исправление, удаление, ошибки сохранения, demo reset/exit и рестарт с личным SwiftData store. Архивы v1 должны читаться, новый экспорт v2 включает взвешивания; старому приложению для чтения v2 нужно обновление. Новых capabilities нет.

Запустите новые AppStoreTests/PersistenceTests и три UI-сценария веса/меню месяца. Проверьте CloudKit на двух устройствах при включённой синхронизации и повторный Watch outbox без потери веса, изменённого на iPhone. [Правила](docs/BODY_WEIGHT.md), [полный checklist](docs/XCODE_VALIDATION.md).

## CSV из FitSession

После обновления выполните `xcodegen generate`: в Info.plist добавлена регистрация системного CSV document type. На iPhone откройте **Настройки → Данные → Импорт и экспорт → Выбрать файл**, выберите первый CSV, проверьте часовой пояс/сводку и подтвердите импорт; затем повторите со вторым файлом. Те же CSV можно открыть из «Файлов» через FitnessTracker. До подтверждения данные не должны меняться, повторный импорт не создаёт копии.

Проверьте множители веса, нулевые/пропущенные подходы, заметки и прочерк вместо неизвестной длительности. HealthKit export без длительности недоступен. Новый JSON-экспорт использует v3 и переносит эти поля; v1/v2 по-прежнему читаются. Запустите новый ArchiveTransferTests CSV flow и AppStoreTests для HealthKit guard. Linux проверил оба пользовательских CSV целиком и Core; picker, file providers, signing и Apple UI требуют Xcode. [Правила и границы](docs/CSV_IMPORT.md).

## AirPods Pro 3: первая проверка на iPhone

После обновления выполните `xcodegen generate`: новые services/views включаются через существующие source directories. Дополнительных background modes или entitlements не добавлено. Проверьте HealthKit и signing в выбранной Personal/full конфигурации, компиляцию AirPodsHeartRateService с Swift 6 и обновлённые RU/EN usage strings. Simulator подходит для интерфейса, но не подтверждает приём с датчика.

На iPhone с iOS 26+ подключите AirPods Pro 3, наденьте их и включите измерение пульса в настройках iOS. FitnessTracker → Настройки → Трекер → AirPods Pro 3 → Apple «Здоровье». Начните тренировку и нажмите «Включить приём пульса». Разрешите чтение пульса/тренировок и запись тренировок. Запись HKWorkout остаётся отдельным экспортом, временный builder отбрасывается. Самими HR samples в Health управляет iOS.

Проверьте реальное измерение, паузу/продолжение, блокировку, снятие наушников, выключение разрешений, смену профиля, завершение и повторное включение. После остановки не должно появляться автоматически сохранённой HKWorkout; явный экспорт завершённого журнала создаёт её один раз. При подключённых Watch система выбирает источник, поэтому пульс не помечается как доказанно полученный только с AirPods. Полный список: [AirPods checklist](docs/XCODE_VALIDATION.md#airpods-pro-3--живой-пульс-healthkit).

## Проверка новых карточек тренировки и упражнения

После обновления с жестом закрытия выполните `git pull --ff-only` и `xcodegen generate` на машине с Xcode: новый `Apple/Design/PullDownToDismiss.swift` должен попасть в app target. В ранней версии была ошибочная запись `.environment(\.refresh, nil)` в read-only API; обновите исходники, если Xcode сообщает `Generic parameter 'V' could not be inferred` на этой строке. В активной/завершённой тренировке и упражнении нет `.refreshable`; жест использует фазы прокрутки. Проверьте закрытие текущего уровня и восстановление сессии по [checklist](docs/XCODE_VALIDATION.md).

Выполните `xcodegen generate`, затем обычную сборку/тесты iOS-схемы. Из активной тренировки и истории нажмите строку упражнения: должна открыться карточка подходов. Проверьте ввод веса/повторов, сохранение через ✓, добавление, паузу/продолжение и стрелки. Завершение доступно отдельной кнопкой; история не позволяет выполнять подходы. Ссылки техники/прогресса должны восстанавливать navigation bar и стандартный возврат. Проверьте клавиатуру, узкий экран, AX Dynamic Type, ошибки сохранения и кг/фунты. Сравните с локальными IMG_1612/1613 и [превью](docs/previews/workout-flow.png); сами превью не подтверждают layout SwiftUI или Liquid Glass.

## Проверка разминки и дропсетов

После обновления выполните xcodegen generate и сборку iOS/Watch/widgets. Новых entitlements и физической SwiftData schema migration нет: новые поля optional в JSON aggregates. В карточке упражнения выберите pending set, укажите положительный вес и откройте ⋯ → Сделать дропсетом; добавьте второй drop. Выполните этапы, проверьте отсутствие отдыха между ними, запуск отдыха после последнего, сохранение, графики и новый экспорт v4. В отдельном подходе включите «Разминочный подход» и проверьте метку и исключение из рабочего объёма. Запустите новые PersistenceTests и testWarmupAndDropStagesCanBeConfiguredBeforeCompletion; Linux их не исполняет. [Сценарии](docs/DROP_SETS.md).

## Проверка цифрового ввода по IMG_1614

После xcodegen generate проверьте сборку WorkoutNumberPad и новые numeric buttons. В активном упражнении нажмите вес/повторы: откроется нижняя панель, первое число заменяет прежнее; › идёт по незавершённым полям, ↓= копирует только подходящие будущие поля, кнопка клавиатуры закрывает её. Проверить десятичную запятую/точку, long-press удаления, аппаратные цифры/Backspace/Return/Escape, позицию поля после inset и AX/landscape/iPad. Поля теперь являются accessibility buttons, UI tests обновлены соответствующим образом. Реальное SDK-поведение, touch/scroll и shortcuts не проверялись на Linux. [Сценарии](docs/NUMBER_ENTRY.md).
