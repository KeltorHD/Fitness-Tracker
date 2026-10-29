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
| SwiftUI: Today, Plans/editor, Session, History/detail, Progress, Settings | Да | Нет, только syntax parse | Да | Signing для устройства |
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

## Фактические проверки

- `swift build`: прошёл для FitSessionCore на Linux.
- `swift test`: прошли 40 Swift Testing tests, включая parameterized cases. Стандартный XCTest runner также печатает «0 tests» — Core использует отдельный Swift Testing runner, его итоговая строка содержит 40 tests.
- Swift formatting/lint, синтаксический разбор Apple Swift, структура/конфигурационные связи, plist/JSON, PNG и наличие ресурсов: прошли в `bash scripts/check-linux.sh`. Для Dynamic Island parser проверяет обе ветви shared intents: основной target с FITSESSION_APP и widget extension без него.
- В текущей рабочей сессии Swift установлен в `/tmp/fitsession-toolchain/swift-6.2.1-RELEASE-ubuntu24.04`; для постоянной установки предусмотрен `setup-linux.sh`, toolchain не хранится в git.
- XcodeGen generation, iOS/watchOS compilation, linking, Simulator, SwiftUI rendering и реальные Apple-сервисы **не проверены**. Linux CI не заменяет эти проверки.

## Границы текущей реализации

Watch записывает отдельный стартовый план и передаёт готовую тренировку на iPhone; live mirroring и датчики HealthKit не реализованы. HealthKit экспортирует workout без вымышленных калорий/пульса. CloudKit использует системную eventual sync без собственного экрана прогресса загрузки и без поэлементного conflict merge. Все функции бесплатны; график за 26 недель доступен без дополнительных условий. Экспорт JSON реализован для отдельной тренировки, импорт архива через UI не реализован.

Дальнейшие исправления после первой сборки на Mac должны сопровождаться обновлением этой таблицы и [Xcode validation checklist](XCODE_VALIDATION.md). Нельзя менять статус Apple-модуля на Linux-tested по результату parser/linter.

Фоновое поведение и ограничения: [BACKGROUND_AND_DYNAMIC_ISLAND.md](BACKGROUND_AND_DYNAMIC_ISLAND.md).

Данные, условия использования и границы локализации: [EXERCISE_LIBRARY.md](EXERCISE_LIBRARY.md).
