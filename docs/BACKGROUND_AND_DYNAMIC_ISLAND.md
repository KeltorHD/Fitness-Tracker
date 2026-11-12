# Фоновая тренировка и Dynamic Island

## Что продолжает работать

При обычном сворачивании FitLife или блокировке iPhone тренировка остаётся активной. Сохранённые даты начала, окончания отдыха и интервалы пауз позволяют восстановить корректное активное время после suspension или перезапуска процесса. Таймер не зависит от `Timer` в фоне.

Live Activity показывает системные SwiftUI `Text(timerInterval:pauseTime:countsDown:showsHours:)`: отсчёт активного времени, замороженное время паузы и обратный отсчёт отдыха, останавливающийся на нуле. Для них не требуется запуск приложения каждую секунду. По окончании отдыха система может доставить заранее запланированное локальное уведомление, если пользователь разрешил уведомления и включил их в FitLife.

В Dynamic Island реализованы:

- **Compact:** значок тренировки/паузы и время отдыха либо активное время.
- **Minimal:** круг прогресса подходов или значок паузы.
- **Expanded:** счётчик подходов, следующее упражнение и номер подхода, время, кнопки Пауза/Продолжить и Пропустить отдых.
- **Lock Screen:** название тренировки, активное время, прогресс, следующий подход и те же действия.
- Нажатие на область активности открывает конкретную тренировку по UUID. На iPhone без Dynamic Island используется Live Activity на Lock Screen.

## Оформление и выбранная тема

Тема приложения передаётся в каждом `WorkoutLiveState` через необязательный colorThemeID. Смена темы запускает обновление существующей активности; её не нужно завершать и создавать заново. Обновляемый заголовок workoutName также передаётся в состоянии. Старые payloads читаются без этих полей: до обновления используется стандартная тема «Лес» и имя из attributes. Доменные данные тренировок не изменяются.

На Lock Screen используется адаптивная светлая/тёмная поверхность, мягкое тонирование и градиентный контур ContainerRelativeShape. Содержимое разбито на заголовок/статус, активное время/следующий подход, прогресс и действия. Во время отдыха показывается системный `ProgressView(timerInterval:countsDown:)`; он изменяется системой без per-second задач в приложении. Числа подходов и пульса используют переходы при обновлении данных с учётом Reduce Motion и Always-On; бесконечных декоративных анимаций нет.

Dynamic Island сохраняет системную чёрную поверхность, а иконки, кольцо и keyline используют светлые акценты выбранной темы с отдельными high-contrast вариантами. Цвета основаны на тёмных вариантах палитры приложения. Недельный виджет получает ту же косметическую настройку через App Group независимо от opt-in сводки; тренировочные данные по-прежнему публикуются только после opt-in.

После этого изменения нужен `xcodegen generate`: общий FitnessColorTheme.swift добавлен в sources widget extension. Реальный рендеринг, размеры и поддержка SDK требуют проверки на Mac/устройстве; Linux не проверяет SwiftUI/ActivityKit types.

Действия выполняют `LiveActivityIntent` в процессе основного приложения без открытия его интерфейса. `FitLifeRuntime` лениво открывает тот же SwiftData store и возвращает единственный AppStore/ModelContext на процесс, в том числе при холодном запуске intent. Сначала действие проверяется и сохраняется, затем код ожидает завершения ActivityKit/notification updates до возврата из `perform()`.

Пауза и продолжение задают желаемое состояние явно: повторная доставка одного действия не создаёт лишних интервалов пауз. Команда пропуска содержит окончание конкретного отдыха; устаревшая кнопка не может сбросить отдых следующего подхода. Действия для завершённого, отменённого или удалённого workout отвергаются.

## Ограничения iOS

iOS может приостановить процесс FitLife; постоянная работа произвольного кода в фоне не запрашивается. Короткий `beginBackgroundTask` используется только для завершения уже подготовленных системных обновлений при сворачивании. Expiration handler отменяет работу и освобождает background task. Сохранение тренировки выполняется синхронно до этого этапа и не зависит от выделенного фонового времени.

Activity.request вызывается синхронно при старте тренировки в foreground. Фоновые обновления изменяют/завершают существующую активность и не пытаются произвольно создавать новую. При возвращении в foreground сервис сверяет `Activity.activities`, обновляет текущую активность, закрывает устаревшие и дубликаты. Отключение Live Activities в FitLife завершает текущую активность.

Live Activity имеет системный лимит активности до 8 часов; она не гарантируется после принудительного завершения пользователем, перезагрузки или отключения Live Activities. Данные самой тренировки остаются в SwiftData. Доступность зависит от устройства и настроек iOS. Кнопки на заблокированном экране могут потребовать аутентификации; в CarPlay действия Live Activity не выполняются.

На нуле таймер отдыха останавливается. Приложение не пробуждается только ради смены надписи: старое поле отдыха очищается при следующем действии/обновлении, а следующий подход виден заранее. Нет фиктивного аудио, polling, Background App Refresh для секундного отсчёта, сервера или ActivityKit push token. Живой пульс AirPods Pro 3 получает отдельная системная сессия HealthKit по явному запуску; это не фоновый polling. Реальная доставка при блокировке/остановке процесса требует проверки на устройстве: [AIRPODS.md](AIRPODS.md).

## Файлы

- `Sources/FitLifeCore/WorkoutLiveState.swift`: компактное состояние, якоря таймеров и идемпотентные действия, тестируемые на Linux.
- `Apple/Widgets/WorkoutLiveActivityWidget.swift`: Dynamic Island и Lock Screen layouts.
- `Apple/Shared/WorkoutActivityIntents.swift`: LiveActivityIntent, параметры и маршрутизация в основной процесс.
- `Apple/App/FitLifeRuntime.swift`: восстановление AppStore для UI и intents.
- `Apple/Services/LiveActivityService.swift`: request/update/end/reconcile.
- `Apple/Services/BackgroundTaskLease.swift`: ограниченное время завершения обновлений.

Shared intents собираются в обоих targets. Только основной target получает `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) FITLIFE_APP`; extension не открывает SwiftData и при неожиданном исполнении intent в своём процессе возвращает ошибку. Widget target теперь также линкует локальный FitLifeCore package. После переноса на Mac снова выполните `xcodegen generate`.

## Проверка

**Implemented:** да. **Linux-tested:** модель состояния, таймерные расчёты, stale/duplicate actions и размер payload. **Requires Xcode validation:** все ActivityKit/AppIntents/SwiftUI/background lifecycle сценарии. **Requires Apple Developer configuration:** обычный signing приложения и widget extension; локальные Live Activities не используют APNs.

На Mac проверьте начало тренировки → немедленное сворачивание; блокировку на несколько минут; корректность секундомера; паузу/продолжение из expanded Island; пропуск отдыха; доставку уведомления; холодный запуск через intent; старую кнопку после начала нового отдыха; завершение тренировки; переключатель Live Activities. Выполните проверки на настоящем iPhone с Dynamic Island, а также Lock Screen на устройстве без него. Реальная компиляция и эти сценарии на Linux не выполнялись.

Официальные источники: [ActivityKit lifecycle и ограничения](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [интерактивные Live Activities и процесс выполнения intents](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [системный Text timer](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)), [выбор фонового механизма](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app), [expiration handler на main thread](https://developer.apple.com/forums/thread/85066/).
