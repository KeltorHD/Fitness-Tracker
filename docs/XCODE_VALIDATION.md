# Проверки, требующие Xcode

Все пункты ниже остаются **непроверенными** до выполнения на macOS/устройстве. Отметьте устройство, ОС, Xcode version, результат и ссылку на исправление при первом прогоне.

## Локализация RU/EN

- [ ] После генерации Localizable.xcstrings компилируется в app/widgets/Watch, InfoPlist.xcstrings — в главном app target; в продукте есть ru.lproj и en.lproj.
- [ ] На RU/EN устройствах «Как на устройстве» выбирает язык по приоритету; неподдерживаемый язык корректно использует следующий поддерживаемый или EN.
- [ ] Настройки → Основные → Язык приложения: переключение RU/EN без перезапуска, сохранение выбора после relaunch, возврат к системному режиму.
- [ ] Переключение не сбрасывает активную тренировку, editor draft, навигацию, заметки и сохранённые названия/UUID.
- [ ] Каталог: одинаковые 100 упражнений, названия/мышцы/инструкции RU/EN, двуязычный поиск, фото в авиарежиме.
- [ ] Вкладки, пустые/ошибочные состояния, импорт/экспорт, даты, единицы, 1/2/5/11/21 тренировка; дробный вес сохраняет региональный decimal separator при другой локали интерфейса.
- [ ] Dynamic Type, длинные EN/RU подписи, VoiceOver и календари в обеих локалях.
- [ ] Недельный виджет обновляет язык после настройки; язык можно передать до opt-in без workout snapshot. Display name виджета и метаданные App Intents следуют системному языку.
- [ ] Активный отдых/Live Activity/Dynamic Island обновляют подписи и имя упражнения при смене языка; старый snapshot без languageCode читается; повторные pause/resume/skip-rest работают.
- [ ] Watch использует язык часов, инструкции остаются офлайн; пользовательские названия тренировок не изменяются.
- [ ] HealthKit usage strings и системные диалоги показываются на системном/назначенном iOS языке приложения.
- [ ] Запустить L10nTests, WidgetSnapshotTests и testLanguageCanBeChangedWithoutRelaunchingTheApp. Эти тесты не запускались на Linux.

Устройство и границы переключателя: [LOCALIZATION.md](LOCALIZATION.md).

## Mi Band / HUAWEI WATCH GT 6 Pro / HealthKit и Bluetooth

- [ ] Модель трекера: Mi Band → HUAWEI WATCH GT 6 Pro → другой; выбор сохраняется после relaunch, не запрашивает permissions и не меняет текущую тренировку/режим/подключение. Проверить RU/EN подсказки и официальный Link.
- [ ] WATCH GT 6 Pro: HUAWEI Health (региональная версия) → HealthKit, фактические записи/источники и отсутствие обещаний полного экспорта.
- [ ] На GT 6 Pro включить HR Data Broadcasts, найти 180D, подписаться на 2A37 и записать реальный пульс; проверить потерю контакта, блокировку, паузу/завершение и возможное отключение HUAWEI Health. Если пункта нет, проверить путь через HealthKit.
- [ ] В Bluetooth показывается имя реально выбранного устройства, а не название профиля; GT 6 Pro и Mi Band остаются доступны без whitelist по имени.
- [ ] После `xcodegen generate` собираются HealthMetricsReader, BluetoothHeartRateService, TrackerView и график истории; проверить Swift 6 SDK actor annotations у delegate/queries.
- [ ] При первом открытии «Трекер» permissions не запрашиваются. Read permissions появляются по кнопке; Bluetooth — по поиску. Выбор режима сохраняется, обе локали RU/EN проверены.
- [ ] Health: Mi Fitness → «Здоровье» → FitnessTracker, шаги/энергия/сон/пульс, реальные source names, дата/часовой пояс/DST, частичные права и пустые данные без ложного диагноза «доступ запрещён».
- [ ] Импорт пульса завершённой тренировки: только heart-rate permission, временные границы/паузы, empty/retry/cancellation; существующая Bluetooth-запись не заменяется.
- [ ] Mi Band 10 с включённым Share HR обнаруживается как Heart Rate Service, подключается и присылает notifications 2A37. Проверить другую Bluetooth HR модель при наличии.
- [ ] Bluetooth denied/off/unsupported, timeout поиска/подключения, contact loss, отключение и явное повторное подключение; старые callbacks от прошлого peripheral не изменяют текущее подключение.
- [ ] Сессия: реальные свежие измерения, отдых записывается, пауза не записывается; после 15 секунд отсутствия пакетов старое число не показывается как текущее.
- [ ] Заблокировать iPhone, проверить уведомления BLE и запись в фоне. Force quit/reboot не обещают продолжение; после открытия checkpoints доступны, подключение восстанавливается вручную.
- [ ] Checkpoint/finish/background expiration: ограниченная работа, отмена pending tasks; ошибка сохранения видна, повтор сохраняет последние точки.
- [ ] История: график со средним/максимумом и разрывами, длительная запись, Dynamic Type, VoiceOver и смена темы. Пройденный UI-тест не заменяет проверку радио.
- [ ] Локальные файлы исключены из backup/CloudKit/App Group и защищены на iOS; JSON/.fitnesstracker, widgets/Live Activity/Watch не содержат новых sensor payloads.
- [ ] Отмена/удаление тренировки удаляет локальный sidecar; повреждённая запись сохраняется с ошибкой, отказ сохранения/чтения не создаёт пустую базу.
- [ ] Запустить `testTrackerOffersBothModesWithoutRequestingPermissionsOnOpen` и весь существующий UI suite. На Linux UI-тест не запускался.

Инструкция и точные ограничения: [MI_BAND.md](MI_BAND.md).

## Переименование в FitnessTracker

- [ ] `xcodegen generate` создаёт FitnessTracker.xcodeproj со схемами FitnessTracker Personal / FitnessTracker / FitnessTrackerWatch / FitnessTrackerWidgets; package FitnessTrackerCore и все test targets разрешаются.
- [ ] Обновление поверх прежней установки с теми же Team/Bundle ID/App Group/CloudKit сохраняет историю, настройки, активную сессию, локальный пульс и Watch outbox; store не удаляется и не создаётся пустым при ошибке.
- [ ] Имя FitnessTracker видно на iPhone/Watch, в widgets, permissions, меню и обоих языках.
- [ ] Установленный виджет обновляется с прежним kind; проверить Live Activity до/после обновления и legacy deep links.
- [ ] `.fitnesstracker` / `.json` экспортируют новый brand и metadata, старые `.fitsession` и JSON version 1 открываются через Files/AirDrop без изменения данных и новых дубликатов.
- [ ] Health export существующей тренировки не создаёт дубликат после переименования.
- [ ] Старые и новые переменные Local.xcconfig дают те же реальные signing identifiers; новых профилей из-за имени продукта не требуется.

Порядок обновления: [RENAME.md](RENAME.md).

## Сборка и тесты (общие сценарии)

- [ ] `xcodegen generate`: spec, local SPM dependency, пять targets и schemes.
- [ ] FitnessTracker Debug/Release compilation: SwiftUI overloads, SwiftData macros, Swift 6 concurrency.
- [ ] ActiveWorkoutView: Section/TimelineView компилируются с @AppStorage weightUnit; смена кг/фунтов обновляет сводку, skip-rest вызывает Core action с expectedEnd и не сбрасывает новый отдых.
- [ ] FitnessTracker Personal: PersonalDebug/PersonalRelease используют PersonalTeam.entitlements без CloudKit/APNs; установлены и запускаются с Personal Team, включая widgets/watch.
- [ ] Personal build с сохранённым cloudSync=true всё равно открывает локальный store и не регистрирует APNs; предпочтение не стирается. Полная схема возвращает iCloud controls.
- [ ] FitnessTrackerWidgets: extension-safe API, shared attributes, assets и Info.plist.
- [ ] FitnessTrackerWatch: single-target application, icon, deployment, companion ID, embedding.
- [ ] iOS unit tests: SwiftData upsert/delete/validation и AppStore DI/export behavior.
- [ ] UI tests: свободная тренировка → упражнение → подход → завершение → история; сворачивание и продолжение.
- [ ] Archive, entitlements и privacy report проверены перед распространением.

## Компоненты SwiftUI / Liquid Glass

| Компонент | Что проверить |
| --- | --- |
| Root TabView / NavigationStack | Нативные панели iOS 26, safe areas, landscape/iPad и подписи вкладок |
| DashboardView / MetricView | Размеры текста, контраст акцента, отсутствие обрезки русских строк |
| SessionControls | Всегда видимая «Завершить тренировку», disabled до первого выполненного подхода и пояснение; `GlassEffectContainer`, `glassEffectID`/`matchedGeometry`, стили glass/glassProminent; горизонтальная/вертикальная раскладка, клавиатура и узкий iPhone |
| RestPill | Нативный `.glassEffect()`, читаемость countdown, остановка на нуле |
| ActiveWorkoutView / SetEditor | decimal separator, кг/фунты, warmup, пауза, повторный completion заблокирован, заметки, отказ сохранения |
| ExercisePicker / CustomExerciseView | Поиск, длинные названия, свой exercise, вложенные sheets |
| TemplatesView / TemplateEditor | Binding коллекций, добавление/удаление exercise, диапазоны и сообщения validation |
| HistoryView / WorkoutDetailView | Empty state, удаление с подтверждением, JSON ShareLink, прогресс export и alerts |
| ProgressScreen / Charts | Пустые данные, бесплатный график за 26 недель, VoiceOver и unit conversion |
| SettingsView | Opt-ins, отсутствие автоматического HealthKit-запроса, все функции доступны бесплатно |
| Live Activity / Dynamic Island | Compact/minimal/expanded и Lock Screen; активное время с pauseTime, отдых до нуля, следующий подход; кнопки pause/resume/skip-rest, cold-launch intent и UUID deep link |
| WeeklyWidgetView | Small/medium, отсутствие opt-in, обновление и смена недели, privacy redaction |
| WatchWorkoutView | Маленький экран, Crown/Stepper, timer при suspension, pause и offline queue |

Для каждого экрана проверьте Light/Dark, Dynamic Type вплоть до accessibility sizes и VoiceOver. Для стекла дополнительно включите Reduce Transparency, Increase Contrast и Reduce Motion. Системные fallback/accessibility adjustments допустимы; собственного blur-подмены в проекте нет.

## Интеграции и восстановление

- [ ] Остановка процесса в active/paused, восстановление подходов, точная длительность и интервалы пауз.
- [ ] HealthKit grant/deny/revoke, длительность, pause events, повторный export того же UUID.
- [ ] CloudKit: valid signing, iCloud account, restart после toggle, два устройства, offline edits/delete, production schema.
- [ ] Notifications: grant/deny, locked-screen rest, pause/finish/skip cancel.
- [ ] Live Activity: отключена пользователем, восстановление после перезапуска, окончание и системные лимиты длительности.
- [ ] LiveActivityService: Swift 6.2 compile без `Sending 'duplicate/activity' risks causing data races`; ID snapshots и @concurrent helpers для end/update. Проверить удаление дублей, пропавший keeper и отмену перед повторным request.
- [ ] Widget App Group: opt-in/off, актуальность после foreground refresh, week rollover.
- [ ] Watch: offline recording, relaunch, transfer failure/retry, idempotent import и acknowledgement после save.

Детали настройки: [MAC_BUILD_GUIDE.md](../MAC_BUILD_GUIDE.md).

## Дополнительно: фон и интерактивная Dynamic Island

- [ ] Перегенерировать проект: FitnessTrackerCore связан с widget extension, FITNESS_TRACKER_APP определён только для main app.
- [ ] Проверить App Intents metadata extraction обоих targets и dispatch LiveActivityIntent в main app.
- [ ] Начать тренировку и немедленно свернуть: Activity.request не откладывается за async notification work.
- [ ] На настоящем iPhone: секундомер и countdown продолжаются при suspension, countdown останавливается на нуле.
- [ ] Pause/resume из Island сохраняют интервалы; возврат в UI показывает те же данные.
- [ ] Холодное выполнение intent открывает единственный SwiftData context, не сбрасывает workout и не создаёт новый план.
- [ ] Повторный pause/resume и старая skip-rest кнопка не портят новую запись.
- [ ] Expiration background task отменяет pending работу и вызывает endBackgroundTask; тренировка уже сохранена.
- [ ] Ограничения locked device, пользовательского запрета Live Activities, force quit/reboot и системного лимита проверены.

Сценарии и границы обещаний: [BACKGROUND_AND_DYNAMIC_ISLAND.md](BACKGROUND_AND_DYNAMIC_ISLAND.md).

## Библиотека упражнений

- [ ] После xcodegen generate проверить SPM resource Bundle.module и folder reference ExerciseMedia только в iOS target.
- [ ] В авиарежиме на первом запуске доступны 100 записей и обе фотографии карточки.
- [ ] Поиск «жим лежа», «молотки», Romanian Deadlift; фильтры мышц/инвентаря и сброс пустой выдачи.
- [ ] Выбор через каталог открывает карточку; Добавить упражнение возвращает правильный UUID в тренировку и план.
- [ ] Техника доступна в активной тренировке, редакторе плана и истории, включая записи до обновления каталога.
- [ ] Фото листаются; длинные русские названия, Dynamic Type, landscape/iPad и VoiceOver проверены.
- [ ] Источник и полный оригинальный текст лицензии доступны без интернета.
- [ ] UI-тест обновлён для нового перехода через карточку; запустить его в Xcode.

Макеты docs/previews явно обозначены как иллюстрации и не засчитываются как пройденные UI-проверки.

## Переработка по референсам

- [ ] Сопоставить дневник, каталог, результаты и настройки с IMG_1594–IMG_1604 на iPhone.
- [ ] Проверить четыре системные вкладки и группировку toolbar buttons в Liquid Glass; собственный blur отсутствует.
- [ ] Даты недели/месяца, начальная пустая история, несколько тренировок за день и разные локали.
- [ ] Карточка completed workout: раскрытие sheet, редактирование, порядок/удаление упражнений, экспорт, сохранение как шаблон и повтор.
- [ ] Повтор после dismiss sheet показывает новую active session, исходная история не меняется.
- [ ] Updated UI tests проходят через вкладку Дневник и выбор упражнения из каталога.
- [ ] Тема авто/light/dark, Dynamic Type, VoiceOver, iPad/landscape, длинные заголовки.
- [ ] Автоблокировка: active foreground → отключена при включённой настройке; paused/background/finished → обычное поведение.
- [ ] Результаты: реальные числа, выбор года/месяца/упражнения, график 26 недель доступен всем.
- [ ] HistoryViewModel/ProgressViewModel: обновление после сохранения, удаления, смены года/месяца, календаря и возвращения в foreground; фильтр дня не сбрасывает предыдущие личные рекорды.
- [ ] Сохранение истории как шаблона: новые IDs, только выполненные подходы, ошибка повреждённой записи не открывает editor.
- [ ] Запустить новые PresentationModelTests, ExerciseImageTests, WidgetSnapshotTests и AppStoreTests: отмена, старые ответы, retry, отказ save/reload и отсутствие ложного успеха.
- [ ] Настройки: уход с экрана при запросе iCloud/notifications, отказ разрешения и повтор; запрос HealthKit остаётся явным.
- [ ] Фото: быстрый скролл и переходы между фотографиями, отмена .task, отсутствие зависания UI на чтении файлов, ошибка ресурса и retry, память cache.
- [ ] При detail/session sheet сообщения показываются одним экраном; editor/picker не конфликтуют с родительским alert.
- [ ] Повреждённая сводка виджета показывает состояние ошибки без удаления данных; открытие приложения восстанавливает сводку либо очищает её после opt-out.

Показатели калорий, веса и замеров из скриншотов не подставляются как данные пользователя. Фото/GIF оригинального приложения не извлекаются. Полная карта: [REFERENCE_DESIGN.md](REFERENCE_DESIGN.md).

## JSON и .fitnesstracker

- [ ] После генерации проверить Info.plist: exported UTI com.fitnesstracker.archive → public.json, extension fitnesstracker, Viewer/Owner; public.json → Alternate; open-in-place enabled.
- [ ] Сохранить полный архив и отдельную тренировку в обоих форматах. Фактические расширения `.json` и `.fitnesstracker` соответствуют выбору; UTF-8, русский текст, дробные даты и IDs сохраняются.
- [ ] Импорт из локальных «Файлов», iCloud Drive и стороннего file provider; старый JSON одной тренировки также читается.
- [ ] Open in FitnessTracker/AirDrop: foreground, background и cold launch; startup store failure → retry не теряет URL.
- [ ] Внешний файл во время active session, detail, создания/редактирования плана, editor/picker: один preview без потери черновиков и активной тренировки.
- [ ] До подтверждения база не меняется. Отмена picker/read/preview не импортирует данные; отказ save оставляет preview для явного retry.
- [ ] Повторный импорт, совпадающий UUID с другими данными, новая активная сессия при существующей: сводка и фактически пропущенные записи совпадают с правилами.
- [ ] Malformed/oversized/unsupported-version file, неизвестное расширение, недоступный iCloud файл, пропавший security-scoped URL: понятная ошибка, исходные данные сохранены.
- [ ] SwiftData: всё одним save, rollback при storage failure; на втором устройстве CloudKit не создаёт дубликатов при повторном импорте.
- [ ] Запустить ArchiveTransferTests, PersistenceTests и новый UI flow настроек; проверить Dynamic Type/VoiceOver, busy states и повтор после отмены.

[Формат и правила переноса](IMPORT_EXPORT.md).

## Демонстрационный профиль

Все пункты требуют Xcode/устройства; Linux parser не проверяет эти сценарии.

- [ ] После `xcodegen generate` открыть демо из настроек: 24 тренировки за восемь недель, три плана; дневник, календарь, графики и рекорды заполнены.
- [ ] Баннер вымышленных данных виден в основных вкладках, деталях, активной тренировке, редакторе плана и импорте/экспорте. Проверить RU/EN, VoiceOver, Dynamic Type и тёмную тему.
- [ ] Изменить/удалить демо-тренировку и план, создать тренировку, импортировать архив, затем перезагрузить набор: снова 24/3 без накопления дубликатов.
- [ ] Вернуться к личным данным: собственные записи/планы и файлы пульса сохранены, включая совпадающие UUID. Настройки оформления/языка общие. Перезапуск процесса открывает личную историю.
- [ ] При активной/приостановленной личной тренировке вход заблокирован; отмена подтверждения не меняет профиль. Проверить переключение при открытии внешнего файла, чтобы не потерять черновик/операцию.
- [ ] Ошибка чтения личного repository при выходе оставляет демо доступным и показывает ошибку; успешный retry возвращает личную историю. Запустить новые AppStoreTests.
- [ ] В демо нет запросов HealthKit/Bluetooth, Live Activity, уведомлений отдыха и публикации виджета. Ранее опубликованная личная сводка не заменяется демо. Проверить завершение предыдущих updates перед входом.
- [ ] При доставке Watch outbox в демо подтверждение не отправляется; после возврата и повторной доставки запись сохраняется в личном профиле один раз.
- [ ] JSON/`.fitnesstracker` экспорт демо содержит явные имена и заметки; импорт в демо не затрагивает SwiftData/CloudKit. На втором устройстве демо не появляется.
- [ ] Запустить UI-тест открытия/выхода; проверить переходы по вкладкам после сброса навигации и повторное открытие/закрытие профиля.

[Состав и ограничения демо](DEMO_DATA.md).

## Доступность завершения тренировки

- [ ] Начать пустую тренировку: кнопка «Завершить тренировку» сразу видна в нижней закреплённой панели без прокрутки, неактивна; текст объясняет необходимость отметить выполненный подход.
- [ ] Добавить упражнение и отметить подход: кнопка включается, пояснение скрывается. Завершить активную тренировку, затем повторить с паузой; запись появляется в дневнике после успешного сохранения.
- [ ] Свернуть и открыть сессию, прокрутить длинную тренировку, открыть клавиатуру веса/повторов: кнопка остаётся доступной; интерактивное скрытие клавиатуры работает. Проверить ошибку сохранения: сессия остаётся открытой для повтора.
- [ ] Узкий iPhone, landscape, английский и крупный Dynamic Type: горизонтальная раскладка при недостатке места заменяется вертикальной; подписи, VoiceOver, disabled-контраст и нажатия проверены на устройстве.
- [ ] Запустить обновлённые `testLogSetAndFindWorkoutInHistory` и `testMinimizedSessionCanBeResumed`. На Linux эти XCTest UI tests не запускались.

Выбор раскладки использует нативный [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits); [Liquid Glass API](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) сохранены. Результат требует проверки rendering и SDK в Xcode.
