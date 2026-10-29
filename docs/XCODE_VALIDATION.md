# Проверки, требующие Xcode

Все пункты ниже остаются **непроверенными** до выполнения на macOS/устройстве. Отметьте устройство, ОС, Xcode version, результат и ссылку на исправление при первом прогоне.

## Сборка и тесты

- [ ] `xcodegen generate`: spec, local SPM dependency, пять targets и schemes.
- [ ] FitSession Debug/Release compilation: SwiftUI overloads, SwiftData macros, Swift 6 concurrency.
- [ ] FitSessionWidgets: extension-safe API, shared attributes, assets и Info.plist.
- [ ] FitSessionWatch: single-target application, icon, deployment, companion ID, embedding.
- [ ] iOS unit tests: SwiftData upsert/delete/validation и AppStore DI/export behavior.
- [ ] UI tests: свободная тренировка → упражнение → подход → завершение → история; сворачивание и продолжение.
- [ ] Archive, entitlements и privacy report проверены перед распространением.

## Компоненты SwiftUI / Liquid Glass

| Компонент | Что проверить |
| --- | --- |
| Root TabView / NavigationStack | Нативные панели iOS 26, safe areas, landscape/iPad и подписи вкладок |
| DashboardView / MetricView | Размеры текста, контраст акцента, отсутствие обрезки русских строк |
| SessionControls | `GlassEffectContainer`, появление finish action, `glassEffectID`/`matchedGeometry`, стили glass/glassProminent; клавиатура и узкий iPhone |
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
- [ ] Widget App Group: opt-in/off, актуальность после foreground refresh, week rollover.
- [ ] Watch: offline recording, relaunch, transfer failure/retry, idempotent import и acknowledgement после save.

Детали настройки: [MAC_BUILD_GUIDE.md](../MAC_BUILD_GUIDE.md).

## Дополнительно: фон и интерактивная Dynamic Island

- [ ] Перегенерировать проект: FitSessionCore связан с widget extension, FITSESSION_APP определён только для main app.
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

Показатели калорий, веса и замеров из скриншотов не подставляются как данные пользователя. Фото/GIF оригинального приложения не извлекаются. Полная карта: [REFERENCE_DESIGN.md](REFERENCE_DESIGN.md).
