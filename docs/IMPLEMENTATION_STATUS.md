# Статусы модулей

Последняя проверка: 2026-11-01, Ubuntu 24.04 x86_64, Swift 6.2.1, Swift language mode 6.

**Implemented** означает наличие реализации в исходниках. **Linux-tested** означает выполнение функциональных тестов соответствующего Core-кода. Синтаксический разбор Apple-файлов и проверка ресурсов не считаются функциональным тестированием SwiftUI или Apple SDK.

| Модуль | Implemented | Linux-tested | Requires Xcode validation | Requires Apple Developer configuration |
| --- | --- | --- | --- | --- |
| Объединение шаблонов при старте | Implemented: множественный выбор с явным запуском; объединение по exercise UUID в порядке выбора, параметры первого вхождения и отдых первого шаблона; исходные шаблоны не меняются | Linux-tested: Core order/dedup/targets, новые row/set/stage IDs, валидация всех входов и ограничение имени; Apple UI только parser/lint | Requires Xcode validation: выбор/снятие/отмена, обновление списка, сохранение/ошибка, VoiceOver, RU/EN и Dynamic Type; новые XCTest/UI tests не запускались | Нет |
| Центральная кнопка начала тренировки | Implemented: выступающая круглая кнопка в общей Liquid Glass панели, выбор сохранённого шаблона/свободного старта; активная сессия продолжается без дубликата | Core regression suite; Apple-исходники только parser/lint, структура и RU/EN ресурсы; новые XCTest/UI tests на Linux не запускались | Requires Xcode validation: геометрия стекла, tab navigation, sheet transitions, отмена, пустой каталог, ошибка сохранения, активная сессия, доступность | Нет новых capabilities |
| Сворачивание верхней карточки пульса в тренировке | Implemented: компактная строка пульса со стрелкой; график/детали раскрываются, карточка остаётся на месте; AppStorage сохраняет вид | Linux-tested: parser/lint/структура/локализация; Apple UI не запускался | Requires Xcode validation: свернуть/развернуть, relaunch, прежняя настройка false, свежесть, demo mode, VoiceOver; запись/Live Activity продолжаются | Нет |
| Единая карточка пульса в активной тренировке | Implemented: нижний WorkoutTrackerCard удалён; текущее значение, график и ошибки сверху, прямой переход в Трекер для подключения/live controls | Linux-tested: parser/lint/структура/локализация; Apple UI не запускался | Requires Xcode validation: одна карточка, переходы и Bluetooth/AirPods controls | Без новых permissions |
| Заголовок активной тренировки в navigation bar | Implemented: отдельные Image/Text для значка и видимого названия над временем, без toolbar Label style; отдельный WorkoutHero убран | Linux-tested: syntax, lint, project/localization; Apple UI не запускался | Requires Xcode validation: длинное название, rename, Dynamic Type, VoiceOver и узкий экран | Нет |
| Выбор измерения на графиках пульса | Implemented: время до секунд и уд/мин, выделенная точка/RuleMark, сохранение выбора после жеста, VoiceOver adjustment; день/live/история | Linux-tested: ближайшая реальная точка, границы, одиночная точка, разрывы и неверная дата; Apple UI только parser/lint | Requires Xcode validation: касание/drag, прокрутка, смена данных, Dynamic Type и VoiceOver | Нет |
| Пульс в Live Activity и Dynamic Island | Implemented: реальный свежий пульс, lock screen/expanded/compact/minimal, события существующих источников, coalescing 5 с и staleDate 15 с | Linux-tested: Core freshness/pause/compatibility и portable выбор источника/disconnect; SwiftUI/ActivityKit только parser/lint | Requires Xcode validation: SDK, размеры острова, stale transition, реальные фоновые доставки и VoiceOver | Существующие HealthKit/Bluetooth разрешения; новых permissions и push нет |
| Выбор мышц на схеме тела в каталоге | Implemented: виды спереди/сзади, шесть групп, общий фильтр со списком и поиском, сброс и accessibility | Linux-tested: parser/lint/ресурсы; Apple XCTest добавлен, не запускался | Requires Xcode validation: hit targets, Dynamic Type, VoiceOver, RU/EN и сочетание фильтров | Нет |
| Обратная связь чтения показателей в «Трекере» и «Пульс и шаги» | Да: загрузка у кнопки, время успешного чтения, количество данных, отсутствие изменений/данных и ошибка | Да: переносимые модели — успех, пустой результат, повтор, новые данные, ошибка и поздний ответ | Да, отображение RU/EN, Dynamic Type и VoiceOver | Нет сверх существующих HealthKit permissions |
| Пульс и шаги: дневной график пульса, шаги за 7 дней, текущий пульс и live-график тренировки | Да: opt-in чтение stepCount/heartRate, foreground anchored updates, все доступные HealthKit-источники; прямой Bluetooth/AirPods используют существующую запись | Да: Core окна/DST/сегменты/лимит точек; HealthChartsViewModel исполнен с fake — opt-in, события, пауза, cancellation, ошибки и устаревшие ответы; SwiftUI/HealthKit не проверены | Да: компиляция SDK, запросы/разрешения, источники/задержки, charts, VoiceOver, UI test testHealthChartsAreAvailableWithoutRequestingAccessOnOpen | Существующий HealthKit capability, read permissions и реальные устройства |
| Протягивание вниз для закрытия упражнения и сворачивания тренировки | Да: нативные вложенные sheets, собственный NavigationStack упражнения; refreshable ограничен лентой дневника | Только синтаксис, структура и lint; Apple UI tests не запускались | Да, интерактивное закрытие одного уровня, отсутствие spinner, сохранение подходов и навигация к технике/прогрессу | Нет |
| Свайпы месяцев в карточке «История» на «Результатах» | Да: внутри неподвижной карточки движется только календарь; разделитель и сводка фиксированы; Reduce Motion без сдвига | PortableProgressChecks: данные соседних месяцев, обновление, декабрь/январь и високосный февраль; жесты на Linux не проверены | Да, UI test testHistoryMonthCanBeSwipedInBothDirections, интерактивная анимация и совместимость с вертикальной прокруткой | Нет |
| Workout/Exercise/Set models, Codable, units | Да | Да | Нет для Core | Нет |
| Templates и стартовые планы | Да | Да | UI отдельно | Нет |
| State machine, валидация, паузы, отдых | Да | Да | Поведение UI отдельно | Нет |
| Volume, 1ПМ, records, недели, streak | Да | Да | Charts отдельно | Нет |
| Repository protocols и Memory repository | Да | Да | Нет для Core | Нет |
| SwiftUI: Дневник, Шаблоны/editor, Session, History/detail, Результаты, Настройки | Да | Нет, только syntax parse | Да | Signing для устройства |
| Liquid Glass: container, effect, ID, transition, glass buttons | Да | Нет, только syntax parse | Да, включая rendering/accessibility | Signing для устройства |
| SwiftData repository и восстановление сессии | Да | Нет, Apple unit tests не запускались | Да, macro expansion/round-trip/ошибки | Нет для локального store |
| CloudKit через SwiftData, проверка аккаунта | Да | Нет | Да, два устройства и production schema | Да, iCloud container, Push, profiles |
| HealthKit export и реальные pause events | Да | Нет | Да, устройство, разрешения и повторный export | Да, HealthKit entitlement/profile |
| Rest notifications | Да | Нет | Да, permissions/background delivery | Обычный signing, разрешение пользователя |
| Live Activity / Dynamic Island / App Intents | Да: таймеры, следующий подход, pause/resume/skip, cold-launch runtime | Core projection/actions — да; Apple API — нет | Да, lifecycle, intents dispatch, layouts и background expiration | Обычный signing, локальные updates без ActivityKit push |
| WidgetKit weekly summary / privacy opt-in | Да | Нет | Да, timeline/App Group/privacy | Да, App Group |
| watchOS set logger, recovery и acknowledged outbox | Да | Нет | Да, paired Watch/iPhone, offline queue | Signing paired targets |
| iOS unit tests | Написаны | Не запускались | Да | Simulator без платных сервисов |
| iOS UI tests | Написаны | Не запускались | Да | Simulator без платных сервисов |
| project.yml / Info / entitlements / assets | Да | Структура/ресурсы проверяются скриптом | Да, XcodeGen + actool + signing | Да для capabilities |
| setup/check scripts и Linux CI | Да | Локальный check script; remote CI ещё не запускался | setup-macos.sh ещё не запускался на Mac | Нет |
| WorkoutLiveState / idempotent Live Actions | Да | Да, 8 новых тестов | UI отдельно | Нет |
| Exercise Library: 876 записей RU/EN, поиск, фильтры; 774 автоматических перевода отмечены | Да | Да, 8 новых тестов | UI отдельно | Нет |
| Локальные фото (1746 JPEG), 11 готовых ИИ-анимаций, SwiftUI-карточки; генерация остальных остановлена | Да | Hashes и структура — да; Apple UI — нет | Да, folder resources, листание, пауза/Reduce Motion/retry анимации, отсутствие исходных материалов, добавление | Обычный signing |
| Иллюстративные PNG/SVG-макеты | Да | Отрендерены и просмотрены | Не заменяют проверку SwiftUI | Нет |
| TrainingJournal: недельная лента, календарь, ЛР; повтор с новыми ID | Да | Да, 7 новых тестов | UI отдельно | Нет |
| Дизайн по 11 референсам, четыре вкладки, темы, автоблокировка | Да | Только syntax parse и lint | Да, SwiftUI/Glass/presentation/idle timer | Обычный signing |
| TrainingReport, сводка месяца, преобразование истории в шаблон | Да | Да, 6 новых тестов, включая ЛР при фильтре дня | UI отдельно | Нет |
| HistoryViewModel / ProgressViewModel: подготовленные данные вне body | Да | Core-проекции — да; ProgressViewModel дополнительно исполнен с ExerciseProgressViewModel без Apple SDK; HistoryViewModel — только type-check | Да, обновление после редактирования/смены периода | Нет |
| ExerciseLibraryViewModel, SettingsViewModel, DI сервисов и cancellation | Да | Только type-check переносимой части; Apple tests не запускались | Да, permissions, retry, устаревшие ответы, sheet/alert | iCloud для проверки аккаунта |
| ExerciseImageLoader actor и ExercisePhotoViewModel | Да | Type-check файлового сервиса; UIKit/Apple tests не запускались | Да, загрузка/ошибка/retry и cache при прокрутке | Нет |
| Warmup/skip-rest через Core; ошибка сохранения не показывает успех | Да | Warmup и LiveAction rules — да; AppStore tests не запускались | Да, ошибки repository и восстановление UI | Нет |
| WidgetSnapshot: явная ошибка чтения, проверка данных, сохранение повреждённого payload | Да | Только type-check; Apple unit tests не запускались | Да, shared defaults и восстановление сводки | App Group |
| WorkoutArchive: JSON/.fitnesstracker codec, legacy JSON, additive import и atomic repository contract | Да | Да, Core codec/merge/Memory repository | SwiftData batch отдельно | Нет |
| ArchiveFileService, Transferable, fileImporter/fileExporter и file URL handling | Да | Синтаксис/ресурсы; Apple tests не запускались | Да, Files/iCloud Drive, UTI, cancellation, cold launch, sheets | Обычный signing, дополнительных capabilities нет |
| ArchiveTransferViewModel, preview/confirmation/retry и экспорт одной/всех тренировок с планами | Да | Core rules — да; Apple models/tests — нет | Да, UI, batch save, повторный импорт и активная сессия | Нет |
| FitnessTracker Personal: отдельные signing configs без iCloud/APNs, локальная SwiftData и guards | Да | Структура/entitlements и type-check AppCapabilities; Apple tests не запускались | Да, generation/signing/run на Personal Team | Бесплатный Apple account, уникальные IDs и разрешения устройства |
| ActivityKit concurrency: end/update по ID через @concurrent helpers, без передачи SDK handles из MainActor | Да | Синтаксис/форматирование; Apple SDK недоступен | Да, устранение compiler diagnostic и lifecycle на устройстве | Как для Live Activity выше |
| AppLanguage: system/ru/en, plurals; библиотека RU/EN с одинаковыми UUID и media | Да | Да, выбор языка, склонения, двуязычный поиск и сохранение данных | UI отдельно | Нет |
| String Catalog RU/EN, переключатель, экраны/уведомления/виджеты/Watch, display language Live State | Да | Catalog coverage/placeholders/воспроизводимость; type-check L10n; Core payload compatibility | Да, compilation/rendering, system language, persistence выбора, Apple unit/UI tests | Нет для локализации; существующий App Group виджета |
| TrackerMetrics, Bluetooth parser, freshness, bounded recording, sleep union | Да | Да, Core tests | Нет для Core | Нет |
| TrackerViewModel / WorkoutHeartRateViewModel / LocalHeartRateRepository | Да | Да, исполняемые проверки Foundation/Observation с fakes и реальными временными файлами; Swift 6 type-check | iOS file protection, lifecycle и UI отдельно | Нет |
| HealthMetricsReader: дневная сводка и пульс тренировки | Да | Нет для HealthKit; только parser/lint | Да, права, источники Mi Fitness, queries и реальные данные | Существующий HealthKit capability/signing |
| BluetoothHeartRateService + Tracker UI + график истории RU/EN | Да | Нет для CoreBluetooth/SwiftUI; Core/переносимые models проверены | Да, iPhone + Mi Band 10, Share HR, background, SDK concurrency и UI-тест | Обычный signing; Bluetooth permission |
| HUAWEI WATCH GT 6 Pro / Mi Band / другой трекер: профили, RU/EN setup guidance и фактическое Bluetooth-имя | Да | Да, выбор/сохранение профиля без изменения mode, данных, connection и permissions; Apple UI test только написан | Да, реальные часы/прошивка, Huawei Health → HealthKit, HR Data Broadcasts, RU/EN UI | Существующий HealthKit и обычный signing; HUAWEI Developer account не требуется |
| FitnessTracker: product/targets/Core rename, RU/EN, новые экспорты и прежние identities | Да | Да, 78 Core tests, старый envelope → новый экспорт, стабильные paths/URLs и aliases, branding validator | Да, Xcode generation и обновление установленного app/Watch/widgets/store | Существующие Team/Bundle ID/App Group/CloudKit |
| DemoWorkoutData / WorkoutWorkspaceRepository: 24 тренировки, 3 плана, изоляция и безопасное переключение | Да | Да, 5 новых Core tests: RU/EN, DST, стабильные IDs, совпадающие UUID, reset и ошибки чтения | Нет для Core | Нет |
| Демо-профиль в настройках, баннеры, reset/выход, guards внешних интеграций | Да | Только syntax parse, ресурсы и lint; AppStore/UI tests написаны, не запускались | Да, переключение, навигация, integration guards и accessibility | Обычный signing; дополнительных capabilities нет |
| SessionControls: компактный ряд «Пауза» значком + «Завершить», без отдельного пояснения; причина disabled доступна VoiceOver | Да | Только syntax parse, локализация и lint; UI tests обновлены, не запускались | Да, клавиатура, Dynamic Type, узкий экран, завершение active/paused | Обычный signing; дополнительных capabilities нет |
| ExerciseProgressReport: пять показателей, exercise identity, периоды и DST | Да | Да, 7 новых Core tests | Нет для Core | Нет |
| ExerciseProgressViewModel: серии, выбор периода/точки, удаление и выделение workout UUID | Да | Да, реальное исполнение Foundation/Observation модели в PortableProgressChecks и Swift 6 type-check | UI отдельно | Нет |
| Swift Charts по упражнениям в Результатах, active workout и истории | Да | Только syntax parse, ресурсы и lint; три UI-сценария написаны, не запускались | Да, Charts SDK, navigation, selection, RU/EN, кг/фунты и accessibility | Обычный signing; дополнительных capabilities нет |
| BodyWeightEntry / Workout.bodyWeightKG / summary / validation / archive v2 migration | Да | Да, 9 новых Core tests: старые payloads, round-trip, kg/lb, rollback, duplicate Watch import и demo isolation | Нет для Core | Нет |
| BodyWeightViewModel / BodyWeightEditorModel | Да | Да, реальное исполнение PortableWeightChecks и Swift 6 type-check | UI отдельно | Нет |
| Карточка Весы, история, вес active/completed workout и SwiftData bodyWeight records | Да | Только syntax parse/resources/lint; Apple unit/UI tests написаны, не запускались | Да, persistence, ошибки сохранения, sheets, keyboard, RU/EN и signing | Существующая конфигурация; новых capabilities нет |
| Результаты по новым референсам: квадратные дни календаря, крупные карточки, нейтральные поверхности и контурные tabs | Да | Только syntax parse/resources/lint; визуальной проверки не было | Да, узкий экран, 4–6 рядов, Dynamic Type, dark mode, TabView symbols и сравнение с референсом | Обычный signing |
| FitSession CSV: parser, обе схемы, UUID v5, zero reps, multiplier и archive v3/v1/v2 migration | Да | Да, 13 новых Core tests и полная проверка обоих пользовательских CSV в Memory repository | Нет для Core | Нет |
| CSV picker/Files, preview, локализованные ошибки и неизвестная длительность | Да | PortableCSVChecks проверяет decode/round-trip/reimport/форматирование; Apple sources — только parser/lint/resources | Да, document types, iCloud Drive, SwiftData и написанные Apple unit tests | Обычный signing; новых capabilities нет |
| AirPods Pro 3: origin совместим со старым sidecar, live session state и защита записей | Да | Да, 2 новых Core tests и PortableAirPodsChecks с реальными TrackerViewModel/DI | Нет для Core; SDK/UI отдельно | Нет для Core |
| AirPodsHeartRateService / явные live controls RU/EN / HealthKit usage strings | Да | Только parser/lint/resources для SDK/SwiftUI; переносимая модель исполнена с fake source | Да, iPhone + AirPods Pro 3, HealthKit concurrency, права, блокировка, отсутствие лишних HKWorkout и UI test | Существующий HealthKit capability/signing, новых entitlements нет |
| WorkoutExercisePresentation / draft validation / summary по row IDs | Да | Да, PortableWorkoutExerciseChecks: ввод, kg/lb precision, drafts, paging, reorder/delete, pause/history guards и Core completion | Нет для переносимой модели | Нет |
| Компактная тренировка и отдельное упражнение по IMG_1612/1613, RU/EN и Liquid Glass dock | Да | Только parser/lint/resources; UI tests обновлены, не запускались | Да, NavigationStack, layout, keyboard, Dynamic Type, VoiceOver и сохранение/ошибки | Обычный signing, новых capabilities нет |
| SVG/PNG превью тренировки, упражнения и просмотра пульса | Да, демонстрационные данные | Да, генерация librsvg/cairo, структура и воспроизводимость | Это иллюстрации; проверка интерфейса в Xcode остаётся обязательной | Нет |
| DropSetStage / валидация и порядок / отдых / статистика / repeat и plannedSets / archive v4 | Да | Да, 13 новых Core tests: rollback, invalid order/targets, даты/IDs, partial finish, zero load, templates и v1–v3 migration | Нет для Core | Нет |
| Редактор этапов, метки разминки/дропсета, Watch и Live Activity stage labels RU/EN | Да | Реальные portable presentation checks; для SwiftUI/SDK только parser/lint/resources, Apple tests написаны | Да, keyboard/accessibility, SwiftData, UI tests, device и Watch/ActivityKit | Существующий signing/capabilities; новых entitlements нет |
| Макет смешанных типов подходов и сравнение SVG/PNG | Да, демо-данные | Генерация/ресурсы; это не тест SwiftUI | Да для реального интерфейса | Нет |
| WorkoutNumberPadModel и скалярная валидация целей | Да | Да, PortableNumberPadChecks и Swift 6 type-check: replacement/delete/decimal, next/copy, readonly guards, legacy reps и точность lb | Нет для переносимой модели | Нет |
| Цифровая панель и underline по IMG_1614, SwiftUI buttons/insets, RU/EN, shortcuts и превью | Да | Для SDK только parser/lint/resources; макеты генерируются, UI tests обновлены/не запускались | Да, scroll timing, hardware/VoiceOver/AX, full hit areas и layout | Обычный signing, новых capabilities нет |


## Фактические проверки

- `swift build`: прошёл для FitnessTrackerCore на Linux.
- `swift test`: прошли 130 Swift Testing tests, включая parameterized cases. Стандартный XCTest runner также печатает «0 tests» — Core использует отдельный Swift Testing runner, его итоговая строка содержит 130 tests.
- Отдельный Swift 6 strict-concurrency type-check без Apple SDK: HistoryViewModel, ProgressViewModel, ExerciseProgressViewModel, BodyWeightViewModel/BodyWeightEditorModel, WorkoutExercisePresentation, ExerciseLibraryViewModel, ExerciseImageLoader, CloudAccountChecking, WidgetSnapshot, AppCapabilities, L10n и WorkoutFormatting. Это проверка типов указанной переносимой части, не функциональный тест и не сборка iOS target.
- Swift formatting/lint, синтаксический разбор Apple Swift, структура/конфигурационные связи, plist/JSON, PNG и наличие ресурсов: прошли в `bash scripts/check-linux.sh`. Для Dynamic Island parser проверяет обе ветви shared intents: основной target с FITNESS_TRACKER_APP и widget extension без него.
- Локализация: 585 ключей RU/EN и четыре InfoPlist-строки, placeholders, формы счётчиков, покрытие русских ключей, target resources и повторяемость генерации — прошли. Компиляция `.xcstrings` в Xcode не проверена; сценарии — [LOCALIZATION.md](LOCALIZATION.md).
- В сессии использован внешний Swift 6.2.1 через SWIFT_BIN; для постоянной установки предусмотрен `setup-linux.sh`, toolchain не хранится в git.
- Исполнен `Tests/PortableHealthChartsChecks/main.swift`: opt-in, пустые данные, события, график текущей тренировки/пауза, cancellation, завершение источника при ошибке потока и поздний ответ после opt-out. Это не тест HealthKit/Charts SDK.
- Переносимая tracker-подсистема дополнительно исполнена в `Tests/PortableTrackerChecks/main.swift`: recording/pause, save failure/retry, mode race, минимальные permissions, history, real file round-trip/corruption/delete. Это не тест HealthKit/CoreBluetooth.
- Исполнен `Tests/PortableProgressChecks/main.swift`: выбор упражнения/точки, периоды, bodyweight, удаление, точный workout UUID при совпадающей дате и связь с ProgressViewModel. Это не тест SwiftUI/Charts.
- Исполнен `Tests/PortableWeightChecks/main.swift`: локализованный и строгий ввод, кг/фунты, точность при правке даты, источники веса, редактирование и смена workspace. Это не SwiftUI/SwiftData test.
- Исполнен `Tests/PortableAirPodsChecks/main.swift`: явный запуск, свежесть/паузы, provenance, сохранение, защита от импорта, поздние callbacks, смена режима/тренировки, отмена, отказ и ошибки загрузки. Источник подставной; HealthKit и AirPods не тестировались.
- Исполнен `Tests/PortableWorkoutExerciseChecks/main.swift`: реальные presentation/draft модели без SwiftUI, включая недопустимые данные, precision в фунтах, повторяющиеся упражнения, навигацию по UUID и запрет выполнения в истории/паузе.
- Исполнен `Tests/PortableNumberPadChecks/main.swift`: реальная Foundation модель и существующие drafts, замена/удаление/разделитель, границы, next/copy isolation, readonly/paused/removal, legacy zero reps и lb precision. Это не UI/keyboard test.
- XcodeGen generation, iOS/watchOS compilation, linking, Simulator, SwiftUI rendering и реальные Apple-сервисы **не проверены**. Linux CI не заменяет эти проверки.

## Границы текущей реализации

Watch записывает отдельный стартовый план и передаёт готовую тренировку на iPhone; live mirroring и датчики HealthKit на Watch не реализованы. На iPhone добавлен явный живой приём через HealthKit для AirPods Pro 3; проверка SDK и реального устройства ещё требуется, автоматическое восстановление системной сессии после завершения процесса не реализовано. [Подключение](AIRPODS.md). HealthKit экспортирует workout без вымышленных калорий/пульса. CloudKit использует системную eventual sync без собственного экрана прогресса загрузки и без поэлементного conflict merge. Все функции бесплатны; график за 26 недель доступен без дополнительных условий. Импорт/экспорт JSON и `.fitnesstracker` реализованы для одной тренировки и полного архива с планами; merge добавляет новые записи без перезаписи существующих. Настройки/permissions и фотографии не включаются в архив.

Дальнейшие исправления после первой сборки на Mac должны сопровождаться обновлением этой таблицы и [Xcode validation checklist](XCODE_VALIDATION.md). Нельзя менять статус Apple-модуля на Linux-tested по результату parser/linter.

Фоновое поведение и ограничения: [BACKGROUND_AND_DYNAMIC_ISLAND.md](BACKGROUND_AND_DYNAMIC_ISLAND.md).

Данные, условия использования и границы локализации: [EXERCISE_LIBRARY.md](EXERCISE_LIBRARY.md).

Перенос дизайна и границы относительно референсов: [REFERENCE_DESIGN.md](REFERENCE_DESIGN.md).

Два режима Mi Band/HealthKit/Bluetooth и границы хранения: [MI_BAND.md](MI_BAND.md).

Переименование и установленные идентификаторы: [RENAME.md](RENAME.md).

Графики по упражнениям и правила периодов: [EXERCISE_PROGRESS.md](EXERCISE_PROGRESS.md).

Изолированные демонстрационные тренировки: [DEMO_DATA.md](DEMO_DATA.md). Демо хранится в памяти и сбрасывается при выходе/завершении процесса; настройки приложения общие с личным профилем.

Фиксация веса и перенос данных: [BODY_WEIGHT.md](BODY_WEIGHT.md).

Импорт двух CSV-вариантов: [CSV_IMPORT.md](CSV_IMPORT.md). Новый экспорт — v4; старые v1/v2/v3 читаются.

Дропсеты и разминка: [DROP_SETS.md](DROP_SETS.md). Полная запись и частичное завершение не создают фиктивно выполненных этапов.

Цифровая панель: [NUMBER_ENTRY.md](NUMBER_ENTRY.md); два новых ввода и общий макет — демонстрационные SVG/PNG.

Группы мышц шаблона: **Implemented**. Несколько необязательных групп сохраняются в Codable payload с additive migration старых шаблонов; подписи видны в каталоге/обзоре/выборе, каталог упражнений сразу фильтруется по объединению групп. Core compatibility/archive/repository/search: **Linux-tested**. SwiftUI и Apple unit tests: **Requires Xcode validation** (сценарии в XCODE_VALIDATION.md).

Параметры выполнения шаблона: **Implemented**. Отдых, подходы, повторения, вес и сводки plannedSets перенесены в общий свёрнутый DisclosureGroup. Новый шаблон использует произвольный отдых (restSeconds = 0, без автоматического таймера); сохранённые значения не меняются. Core default/start/timed-rest compatibility: **Linux-tested**. SwiftUI: **Requires Xcode validation**.

Множественный фильтр инвентаря: **Implemented**. Меню поддерживает независимые отметки нескольких типов; объединение типов пересекается с группами мышц и поиском, пустой выбор означает весь инвентарь. Core search: **Linux-tested**; переносимая модель — Swift 6 type-check и исполнение с реальным Core (объединение типов, поиск/мышцы, язык, снятие отметки и сброс). SwiftUI/Apple XCTest: **Requires Xcode validation**.

Дни тренировок шаблона: **Implemented**. Необязательный набор preferredWeekdays с additive migration старых payloads; выбор в «Параметрах выполнения», группы «На сегодня»/«Другие шаблоны» без дублей и без автоматического выбора, обновление дня/foreground. Core schedule/archive/repository/legacy/timezone/DST: **Linux-tested**. SwiftUI и системные события времени: **Requires Xcode validation**.

WorkoutNavigationBar contrast environment: **Implemented** — ключ исправлен на официальный colorSchemeContrast, чтение и сравнение используют одноимённое свойство. Linux syntax parse/lint; **Requires Xcode validation** для SDK-компиляции и Increase Contrast.

Панель навигации с центральным стартом: **Implemented** — выбранная капсула использует настоящий glassEffect/ID/matchedGeometry, drag-preview через GestureState и переключение по отпусканию над вкладкой; при отмене/отпускании вне вкладок выбор сохраняется. Старт уменьшен до 52 pt, подъём контура до 12 pt, убраны непрозрачная подложка и белый ободок, центральная кнопка остаётся отдельным действием. Reduce Motion отключает анимации. Linux: syntax/lint/structure; **Requires Xcode validation**, добавлен UI test (не запускался).

Стиль журнала с индиго: **Implemented**. Общий адаптивный AccentColor для app/widgets/Watch, AccentForeground для сплошных акцентных поверхностей и светлый AccentOnDark для чёрного фона Live Activity/Island; спокойные заголовки вместо цветных шапок; округлые карточки сохранены, метрики объединены в одну сводку. Подходы показываются по колонкам с активной строкой/readonly completion, AX перестроением и выровненными дроп-этапами. Linux: syntax/lint/structure/resources/localization; **Requires Xcode validation** для SDK, Asset Catalog compilation, цветов стекла, layout, VoiceOver и UI tests.
