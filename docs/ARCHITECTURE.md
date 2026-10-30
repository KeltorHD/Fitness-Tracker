# Архитектура и данные

## Границы сборки

SPM собирает только `Sources/FitnessTrackerCore` и `Tests/FitnessTrackerCoreTests`. Core зависит от Foundation, использует Swift 6 value types, Codable/Sendable и Swift Testing. Apple SDK не подменяется заглушками. Apple-файлы принадлежат XcodeGen targets и не входят в Linux package. Поэтому `#if canImport(SwiftUI)` вокруг целых экранов не требуется: разделение обеспечивается составом targets.

`AppStore` получает repository, HealthKit exporter, notification service, cloud account checker и image loader через initializer. `SwiftDataWorkoutRepository` и `HealthKitService` реализуют протоколы Core. `MemoryWorkoutRepository` используется в тестах. Все repository-операции изолированы MainActor; SwiftData `ModelContext` не пересекает actor boundaries. WCSession callbacks передают Sendable Data/ошибки в MainActor, сохраняя acknowledgement после записи.

Feature models `HistoryViewModel`, `ProgressViewModel`, `ExerciseLibraryViewModel` и `SettingsViewModel` используют `@Observable`/MainActor. Core TrainingReport подготавливает графики и календарь; запросы, сортировка и сводки обновляются при изменении входных данных, а не при каждом вызове View.body. Фильтр дня сравнивает ЛР со всей предшествующей историей. WorkoutEngine создаёт шаблон из выполненных подходов и проверяет изменение warmup. Общие карточки и форматирование длительности находятся в Apple/Design.

SwiftUI `.task` управляет загрузкой фото, проверкой iCloud, запросом уведомлений, экспортом и реакцией на scene phase. SettingsViewModel отбрасывает устаревшие ответы; отмена не превращается в ошибку. ExerciseImageLoader читает локальные файлы и хранит ограниченный cache Data на отдельном actor; только Data пересекает границу с UIKit. Loader создаётся через DI, глобального image singleton нет.

AppStore публикует новый snapshot только после успешного чтения workouts и templates. Отказ сохранения не изменяет UI-модель и не сообщает об успехе. AppErrorReporter показывает локализованные доменные ошибки либо понятное сообщение операции; диагностические логи содержат только operation/domain/code. WidgetSnapshot сообщает об ошибках чтения, сохраняет повреждённые данные и восстанавливается при следующей публикации.

## Правила тренировки

`ExerciseProgressReport` объединяет повторяющиеся строки одного exercise UUID в одну точку на завершённую тренировку и подготавливает пять показателей рабочих подходов. `ExerciseProgressViewModel` хранит выбранное упражнение, период, серии и ближайшую выбранной дате точку; вычисления выполняются при обновлениях данных/выбора. `ProgressViewModel` использует эту модель вместе с прежней календарной сводкой. Из тренировки открывается та же модель с фиксированным exercise UUID и выделением workout UUID; чужое упражнение при удалении истории не подставляется. [Правила графиков](EXERCISE_PROGRESS.md).

`WorkoutWorkspaceRepository` оборачивает полученный через DI личный repository. В демо-профиле все операции направляются в отдельный `MemoryWorkoutRepository`, без второго SwiftData context. `DemoWorkoutData` создаёт проверяемый архив через обычные Core-правила. Смена профиля сбрасывает presentation state; ошибка чтения личных данных сохраняет текущий демо-профиль. В AppStore отключены экспорт HealthKit, запись датчиков, импорт Watch, Live Activities, уведомления и публикация виджета для демо. Личные настройки общие. [Демо-данные и ограничения](DEMO_DATA.md).

- Workout: active → paused → active, active/paused → completed либо cancelled. После завершения подходы не изменяются.
- Нельзя завершить сессию без выполненного подхода; можно закончить часть запланированных подходов.
- Каждый подход имеет отдельный UUID; повторный completion отвергается. UUID упражнения каталога стабилен между сессиями для статистики.
- Вес хранится только в кг; отображение в фунтах — преобразование на границе UI. Нулевой вес обозначает отсутствие добавленного отягощения.
- Объём = сумма `кг × повторы` только выполненных рабочих подходов. Разминки не включаются. Это объём внешнего отягощения, а не биомеханическая работа.
- 1ПМ рассчитывается по Эпли для 1–12 повторений; одиночное повторение равно указанному весу. Это оценка для графика, не предписание нагрузки.
- Паузы сохраняются точными интервалами. Активная длительность исключает их; таймер отдыха хранит абсолютную дату окончания и не требует фонового процесса.
- Статистика учитывает completed, исключает cancelled, незавершённые и будущие тренировки. Недели определяет Calendar пользователя, включая locale/time zone и начало недели. Серия допускает ещё пустую текущую неделю.
- Сохранение происходит после каждой успешной мутации. При ошибке валидации/записи предыдущая версия остаётся доступной.

## SwiftData / CloudKit

`StoredRecord` хранит versioned JSON-агрегат одной тренировки или шаблона (`kind`, `recordID`, `payload`, `modifiedAt`, `schemaVersion`). Все поля имеют defaults, unique constraints отсутствуют. UUID внутри payload обеспечивает идемпотентность upsert и Watch import. При обнаружении дубликатов чтение выбирает запись с наиболее поздним `modifiedAt`; следующий upsert удаляет лишние локальные records.

CloudKit отключён по умолчанию. Переключение режима применяется при следующем запуске к тому же именованному хранилищу. Включённый режим использует `ModelConfiguration.cloudKitDatabase = .private(containerID)`. Подписанные capabilities и CloudKit schema пользователь настраивает на Mac. Нет ручного дублирующего upload/download поверх SwiftData.

Синхронизация eventual, конфликты решаются системой на уровне последней записи агрегата. Одновременное редактирование одной сессии на двух устройствах не объединяет подходы поэлементно. `modifiedAt` — клиентское время, не глобальные часы. Следует редактировать активную тренировку на одном устройстве. Несколько незавершённых тренировок от разных устройств сохраняются; приложение открывает последнюю, после её завершения доступна предыдущая. Проверка `CKContainer.accountStatus` сообщает только доступность аккаунта.

`schemaVersion = 1` — первая схема; при последующих несовместимых изменениях нужно добавить миграцию JSON и SwiftData schema migration plan. Повреждённые записи не игнорируются молча и не вызывают очистку всей базы: пользователь получает ошибку чтения.

WorkoutArchive — отдельный версионированный формат экспорта JSON/`.fitnesstracker`, с датами в Unix seconds. Core-кодек валидирует весь файл до построения ArchiveImportPlan. WorkoutRepository.importArchive добавляет только новые UUID атомарно: Memory repository меняет snapshot, SwiftData кодирует все payloads перед insert и делает один save/rollback. Между preview и подтверждением план пересчитывается. Текущая активная сессия сохраняется, повторный импорт идемпотентен. Старый JSON одной Workout с ISO-8601 датами поддерживается.

ArchiveFileService выполняет bounded coordinated read и JSON processing на actor; балансирует security-scoped access и передаёт MainActor только WorkoutArchive/Data. ArchiveTransferViewModel получает service, snapshot/plan/commit через DI. SwiftUI fileImporter/fileExporter и Transferable обслуживают оба расширения; exportingCondition фиксирует выбранный тип. Pending file URL сохраняется в памяти во время startup/retry. Общий workflow показывается над текущим экраном без закрытия активной сессии и черновиков редакторов. [Формат и правила](IMPORT_EXPORT.md).

## Apple-сервисы

HealthKit запрашивает только запись workout по действию пользователя. Builder передаёт реальные даты и pause/resume events, стабильный sync identifier/version. Не создаёт фиктивные calorie/heart-rate samples. HealthMetricsReader отдельно читает шаги/активную энергию/сон/пульс по явному запросу; импорт пульса завершённой тренировки запрашивает только heart rate. BluetoothHeartRateService принимает стандартный Heart Rate Service через CoreBluetooth на main queue. TrackerViewModel получает сервисы и файловый repository через DI. Записи пульса хранятся отдельно от Workout в защищённых локальных файлах, исключённых из backup, CloudKit, App Group и JSON/.fitnesstracker; schema журнала и старые payloads не изменены. [Два режима трекера](MI_BAND.md). Все функции бесплатны; график объёма за 26 недель доступен каждому пользователю.

ActivityKit использует локальные request/update/end без push token и восстанавливает доступные activities через `Activity.activities`. Dynamic Island и Lock Screen получают Core-проекцию WorkoutLiveState с системными таймерами и следующим подходом. LiveActivityIntent выполняет pause/resume/skip-rest в основном процессе через общий FitnessTrackerRuntime; UI и intents используют один AppStore/ModelContext. Запись происходит до await обновлений. Live Activities имеют системные ограничения длительности. При сворачивании ограниченный beginBackgroundTask завершает pending updates с обработкой expiration; постоянный background service не запрашивается. Уведомления отдыха отдельны и включаются пользователем.

Виджет читает добровольно опубликованную минимальную сводку из App Group UserDefaults. История не передаётся extension. Timeline учитывает смену недели, но актуальные изменения после CloudKit sync могут потребовать открытия приложения/обновления сводки. Отключение публикации удаляет сводку и запрашивает reload; окончательное расписание обновлений определяет WidgetKit.

## Watch

Watch — автономный журнал подходов по начальному плану, использующий те же Core-правила. Archive в Application Support атомарно хранит active workout и completed outbox. WCSession `transferUserInfo` ставит данные в системную очередь. iPhone подтверждает UUID только после успешного repository save. Watch удаляет outbox item только по подтверждению. Потерянное подтверждение ведёт к безопасной повторной передаче с тем же UUID.

План и активная тренировка не зеркалируются с iPhone; live heart-rate, HKWorkoutSession и длительное workout-processing в этой реализации не используются. Timestamps продолжают корректно отсчитывать время при системном suspension. Экспорт в HealthKit выполняется с iPhone после импорта. Ошибки чтения Watch archive показываются пользователю; файл автоматически не удаляется.

## Проверяемость

Linux проверяет Core compilation/tests, ресурсы/конфигурационные связи, Swift formatting и синтаксис Apple-файлов. Явно выбранные Foundation/Observation модели и файловые контракты дополнительно проходят Swift 6 strict-concurrency type-check без Apple SDK и без заглушек. Только Xcode сможет проверить SDK availability, SwiftUI overload resolution, SwiftData macro expansion, signing, extension embedding, rendering, WCSession и CloudKit. Положительный Linux-результат не повышает Apple-модуль до статуса полностью протестированного.

Подробности: [фон и Dynamic Island](BACKGROUND_AND_DYNAMIC_ISLAND.md).

## Библиотека упражнений

ExerciseLibraryEntry хранит дополнительные данные отдельно от Exercise, поэтому прежний JSON тренировок не меняется. SPM resource содержит русские записи и источник, iOS-only folder — оригинальные фотографии; Watch/widgets не получают 13 МБ media. Восемь прежних UUID сопоставлены с source IDs явно, остальные получены детерминированным UUID v5. Подробности импорта и проверок: [EXERCISE_LIBRARY.md](EXERCISE_LIBRARY.md).

## Дневник и оформление по референсам

TrainingJournal в Core группирует completed sessions по неделям, строит календарь без предположения о 24-часовых сутках и считает улучшения рабочего веса. Repeat создаёт новые session/exercise-row/set UUID, сохраняя identity упражнений. AppStore поддерживает сохранение правок completed workouts с прежней валидацией. FitTheme централизует оранжевую палитру; RootView содержит четыре системные вкладки. Смена темы и idle timer принадлежат Apple layer. Подробности: [REFERENCE_DESIGN.md](REFERENCE_DESIGN.md).
