# Статусы модулей

Последняя проверка: 2026-10-29, Ubuntu 24.04 x86_64, Swift 6.2.1, Swift language mode 6.

**Implemented** означает наличие реализации в исходниках. **Linux-tested** означает выполнение функциональных тестов соответствующего Core-кода. Синтаксический разбор Apple-файлов и проверка ресурсов не считаются функциональным тестированием SwiftUI или Apple SDK.

| Модуль | Implemented | Linux-tested | Requires Xcode validation | Requires Apple Developer configuration |
| --- | --- | --- | --- | --- |
| Workout/Exercise/Set models, Codable, units | Да | Да | Нет для Core | Нет |
| Templates и стартовые планы | Да | Да | UI отдельно | Нет |
| State machine, валидация, паузы, отдых | Да | Да | Поведение UI отдельно | Нет |
| Volume, 1ПМ, records, недели, streak | Да | Да | Charts отдельно | Нет |
| Repository protocols и Memory repository | Да | Да | Нет для Core | Нет |
| SwiftUI: Дневник, Каталог/editor, Session, History/detail, Результаты, Настройки | Да | Нет, только syntax parse | Да | Signing для устройства |
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
| Exercise Library: 100 русских записей, поиск, фильтры | Да | Да, 8 новых тестов | UI отдельно | Нет |
| Локальные фото (200 JPEG), SwiftUI-карточки и выбор упражнений | Да | Hashes и структура — да; Apple UI — нет | Да, folder resources, листание, добавление | Обычный signing |
| Иллюстративные PNG/SVG-макеты | Да | Отрендерены и просмотрены | Не заменяют проверку SwiftUI | Нет |
| TrainingJournal: недельная лента, календарь, ЛР; повтор с новыми ID | Да | Да, 7 новых тестов | UI отдельно | Нет |
| Дизайн по 11 референсам, четыре вкладки, темы, автоблокировка | Да | Только syntax parse и lint | Да, SwiftUI/Glass/presentation/idle timer | Обычный signing |
| TrainingReport, сводка месяца, преобразование истории в шаблон | Да | Да, 6 новых тестов, включая ЛР при фильтре дня | UI отдельно | Нет |
| HistoryViewModel / ProgressViewModel: подготовленные данные вне body | Да | Core-проекции — да; Apple models — нет | Да, обновление после редактирования/смены периода | Нет |
| ExerciseLibraryViewModel, SettingsViewModel, DI сервисов и cancellation | Да | Только type-check переносимой части; Apple tests не запускались | Да, permissions, retry, устаревшие ответы, sheet/alert | iCloud для проверки аккаунта |
| ExerciseImageLoader actor и ExercisePhotoViewModel | Да | Type-check файлового сервиса; UIKit/Apple tests не запускались | Да, загрузка/ошибка/retry и cache при прокрутке | Нет |
| Warmup/skip-rest через Core; ошибка сохранения не показывает успех | Да | Warmup и LiveAction rules — да; AppStore tests не запускались | Да, ошибки repository и восстановление UI | Нет |
| WidgetSnapshot: явная ошибка чтения, проверка данных, сохранение повреждённого payload | Да | Только type-check; Apple unit tests не запускались | Да, shared defaults и восстановление сводки | App Group |
| WorkoutArchive: JSON/.fitsession codec, legacy JSON, additive import и atomic repository contract | Да | Да, Core codec/merge/Memory repository | SwiftData batch отдельно | Нет |
| ArchiveFileService, Transferable, fileImporter/fileExporter и file URL handling | Да | Синтаксис/ресурсы; Apple tests не запускались | Да, Files/iCloud Drive, UTI, cancellation, cold launch, sheets | Обычный signing, дополнительных capabilities нет |
| ArchiveTransferViewModel, preview/confirmation/retry и экспорт одной/всех тренировок с планами | Да | Core rules — да; Apple models/tests — нет | Да, UI, batch save, повторный импорт и активная сессия | Нет |
| FitSession Personal: отдельные signing configs без iCloud/APNs, локальная SwiftData и guards | Да | Структура/entitlements и type-check AppCapabilities; Apple tests не запускались | Да, generation/signing/run на Personal Team | Бесплатный Apple account, уникальные IDs и разрешения устройства |
| ActivityKit concurrency: end/update по ID через @concurrent helpers, без передачи SDK handles из MainActor | Да | Синтаксис/форматирование; Apple SDK недоступен | Да, устранение compiler diagnostic и lifecycle на устройстве | Как для Live Activity выше |

## Фактические проверки

- `swift build`: прошёл для FitSessionCore на Linux.
- `swift test`: прошли 67 Swift Testing tests, включая parameterized cases. Стандартный XCTest runner также печатает «0 tests» — Core использует отдельный Swift Testing runner, его итоговая строка содержит 67 tests.
- Отдельный Swift 6 strict-concurrency type-check без Apple SDK: HistoryViewModel, ProgressViewModel, ExerciseLibraryViewModel, ExerciseImageLoader, CloudAccountChecking, WidgetSnapshot. Это проверка типов указанной переносимой части, не функциональный тест и не сборка iOS target.
- Swift formatting/lint, синтаксический разбор Apple Swift, структура/конфигурационные связи, plist/JSON, PNG и наличие ресурсов: прошли в `bash scripts/check-linux.sh`. Для Dynamic Island parser проверяет обе ветви shared intents: основной target с FITSESSION_APP и widget extension без него.
- В текущей рабочей сессии Swift установлен в `/tmp/fitsession-toolchain/swift-6.2.1-RELEASE-ubuntu24.04`; для постоянной установки предусмотрен `setup-linux.sh`, toolchain не хранится в git.
- XcodeGen generation, iOS/watchOS compilation, linking, Simulator, SwiftUI rendering и реальные Apple-сервисы **не проверены**. Linux CI не заменяет эти проверки.

## Границы текущей реализации

Watch записывает отдельный стартовый план и передаёт готовую тренировку на iPhone; live mirroring и датчики HealthKit не реализованы. HealthKit экспортирует workout без вымышленных калорий/пульса. CloudKit использует системную eventual sync без собственного экрана прогресса загрузки и без поэлементного conflict merge. Все функции бесплатны; график за 26 недель доступен без дополнительных условий. Импорт/экспорт JSON и `.fitsession` реализованы для одной тренировки и полного архива с планами; merge добавляет новые записи без перезаписи существующих. Настройки/permissions и фотографии не включаются в архив.

Дальнейшие исправления после первой сборки на Mac должны сопровождаться обновлением этой таблицы и [Xcode validation checklist](XCODE_VALIDATION.md). Нельзя менять статус Apple-модуля на Linux-tested по результату parser/linter.

Фоновое поведение и ограничения: [BACKGROUND_AND_DYNAMIC_ISLAND.md](BACKGROUND_AND_DYNAMIC_ISLAND.md).

Данные, условия использования и границы локализации: [EXERCISE_LIBRARY.md](EXERCISE_LIBRARY.md).

Перенос дизайна и границы относительно референсов: [REFERENCE_DESIGN.md](REFERENCE_DESIGN.md).
