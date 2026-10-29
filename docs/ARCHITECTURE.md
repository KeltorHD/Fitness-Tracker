# Архитектура и данные

## Границы сборки

SPM собирает только `Sources/FitSessionCore` и `Tests/FitSessionCoreTests`. Core зависит от Foundation, использует Swift 6 value types, Codable/Sendable и Swift Testing. Apple SDK не подменяется заглушками. Apple-файлы принадлежат XcodeGen targets и не входят в Linux package. Поэтому `#if canImport(SwiftUI)` вокруг целых экранов не требуется: разделение обеспечивается составом targets.

`AppStore` получает `WorkoutRepository` и `HealthWorkoutExporting` через initializer. `SwiftDataWorkoutRepository` и `HealthKitService` реализуют протоколы Core. `MemoryWorkoutRepository` используется в тестах. Все repository-операции изолированы MainActor; SwiftData `ModelContext` не пересекает actor boundaries. WCSession callbacks передают только Sendable `Data`/строки в MainActor.

## Правила тренировки

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

`schemaVersion = 1` — первая схема; при последующих несовместимых изменениях нужно добавить миграцию JSON и SwiftData schema migration plan. Повреждённые записи не игнорируются молча и не вызывают очистку всей базы: пользователь получает ошибку чтения. Архив JSON сейчас экспортируется на уровне одной тренировки; импорт архива через UI не реализован.

## Apple-сервисы

HealthKit запрашивает только запись workout по действию пользователя. Builder передаёт реальные даты и pause/resume events, стабильный sync identifier/version. Не создаёт фиктивные calorie/heart-rate samples. Чтение HealthKit не требуется. StoreKit предоставляет разовую Pro-покупку; доступ выдаётся по verified current entitlements, включая отзыв. Периодика подписок не используется.

ActivityKit использует локальные request/update/end без push token и восстанавливает доступные activities через `Activity.activities`. Dynamic Island и Lock Screen получают Core-проекцию WorkoutLiveState с системными таймерами и следующим подходом. LiveActivityIntent выполняет pause/resume/skip-rest в основном процессе через общий FitSessionRuntime; UI и intents используют один AppStore/ModelContext. Запись происходит до await обновлений. Live Activities имеют системные ограничения длительности. При сворачивании ограниченный beginBackgroundTask завершает pending updates с обработкой expiration; постоянный background service не запрашивается. Уведомления отдыха отдельны и включаются пользователем.

Виджет читает добровольно опубликованную минимальную сводку из App Group UserDefaults. История не передаётся extension. Timeline учитывает смену недели, но актуальные изменения после CloudKit sync могут потребовать открытия приложения/обновления сводки. Отключение публикации удаляет сводку и запрашивает reload; окончательное расписание обновлений определяет WidgetKit.

## Watch

Watch — автономный журнал подходов по начальному плану, использующий те же Core-правила. Archive в Application Support атомарно хранит active workout и completed outbox. WCSession `transferUserInfo` ставит данные в системную очередь. iPhone подтверждает UUID только после успешного repository save. Watch удаляет outbox item только по подтверждению. Потерянное подтверждение ведёт к безопасной повторной передаче с тем же UUID.

План и активная тренировка не зеркалируются с iPhone; live heart-rate, HKWorkoutSession и длительное workout-processing в этой реализации не используются. Timestamps продолжают корректно отсчитывать время при системном suspension. Экспорт в HealthKit выполняется с iPhone после импорта. Ошибки чтения Watch archive показываются пользователю; файл автоматически не удаляется.

## Проверяемость

Linux проверяет Core compilation/tests, ресурсы/конфигурационные связи, Swift formatting и синтаксис Apple-файлов. Только Xcode сможет проверить SDK availability, SwiftUI overload resolution, SwiftData macro expansion, signing, extension embedding, rendering, WCSession, CloudKit и покупки. Положительный Linux-результат не повышает Apple-модуль до статуса полностью протестированного.

Подробности: [фон и Dynamic Island](BACKGROUND_AND_DYNAMIC_ISLAND.md).

## Библиотека упражнений

ExerciseLibraryEntry хранит дополнительные данные отдельно от Exercise, поэтому прежний JSON тренировок не меняется. SPM resource содержит русские записи и источник, iOS-only folder — оригинальные фотографии; Watch/widgets не получают 13 МБ media. Восемь прежних UUID сопоставлены с source IDs явно, остальные получены детерминированным UUID v5. Подробности импорта и проверок: [EXERCISE_LIBRARY.md](EXERCISE_LIBRARY.md).
