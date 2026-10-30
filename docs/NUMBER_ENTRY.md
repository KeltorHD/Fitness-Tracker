# Цифровая панель по IMG_1614

В активной тренировке нажмите вес или повторы незавершённого подхода. Число подчёркивается оранжевым, снизу открывается SwiftUI-панель 1–9 / разделитель / 0 / удаление. Первое нажатие цифры заменяет прежнее значение целиком; следующие дописывают его. До первой цифры Backspace очищает выделенное значение, затем удаляет по одному символу. Удержание удаления повторяет действие.

- **›** проверяет текущее число и переходит от веса к повторам, затем к следующей незавершённой строке. Завершённые строки пропускаются; после последнего поля панель закрывается. Этапы дропсета входят в этот порядок.
- **↓=** копирует текущее поле вниз в этом упражнении. Вес копируется в следующие строки без дропсетов, включая разминки; все веса дропсетов сохраняются. Число повторений копируется и в следующие незавершённые этапы дропсетов. Выполненные строки и другие упражнения не затрагиваются. Показывается число обновлённых строк.
- **Клавиатура со стрелкой вниз** закрывает панель, сохраняя введённые цели в черновиках текущего экрана. Дробный разделитель доступен только для веса, соответствует региону; кг/фунты сохраняют прежние правила преобразования.

Строки разминки и дропсета используют ту же панель. На паузе и в завершённой истории редактирование недоступно. Панель закрывается при внешнем выполнении строки, паузе, смене упражнения, удалении тренировки и переходе на другой экран. Пока она открыта, нижние session controls и вспомогательные ссылки скрыты; после закрытия возвращаются. Выбранная строка прокручивается в видимую область, учитывается Reduce Motion.

Это ввод целей, а не отметка выполненной работы: данные записываются в тренировку при ✓ через прежние правила Core/AppStore. Открытие/переход без изменения сохраняют исходную точность веса, включая фунты. Неверный ввод не переносится в следующие строки и не завершает подход. Архивы и SwiftData schema не менялись.

Для аппаратной клавиатуры предусмотрены SwiftUI shortcuts: цифры, локальный разделитель, Backspace, Return для следующего поля и Escape для закрытия. Фактическую маршрутизацию и удержание необходимо проверить на iPhone/iPad. У цифровых кнопок полная область нажатия; поля и действия имеют RU/EN accessibility labels, значения и selected trait.

## Реализация и проверки

`WorkoutNumberPadModel` — Foundation/Observation presentation model с DI существующего WorkoutExercisePresentation. Он управляет полем, заменой/добавлением цифр, переходом, проверкой и копированием черновиков; не работает с persistence или Apple SDK. `WorkoutNumberPad` и числовые кнопки WorkoutSetRow — SwiftUI, без UIKit inputView, TextField-клавиатуры или web UI. SessionControls сохраняют нативный Liquid Glass. Временный ввод не запускает HealthKit и не меняет выполнение подходов.

- **Implemented:** цифровые кнопки, подсветка/underline, replacement, next/copy/hide, decimal/delete/repeat, RU/EN, hardware shortcuts, numeric controls и макеты.
- **Linux-tested:** реальные PortableNumberPadChecks: ввод/границы/разделитель, удаление, порядок полей, copy isolation, неизменяемые выполненные строки, пауза/удаление, legacy zero reps и точность фунтов. Все 127 Core tests и существующие portable checks прошли. SwiftUI — только parser/lint/resources.
- **Requires Xcode validation:** SwiftUI types, tap regions, inset/scroll timing, landscape/iPad/AX, VoiceOver, physical shortcuts и UI tests. Обновлён тест конфигурации дропсета; добавлен testNumberPadReplacesValuesAndCopiesFollowingRepetitions. Они не запускались на Linux.
- **Requires Apple Developer configuration:** обычный signing; новых capabilities нет.

## Превью и источники

[Вес и повторы рядом](previews/number-entry-overview.png), [редактирование повторов](previews/number-entry.png), [редактирование веса](previews/weight-entry.png). Это явно подписанные иллюстративные макеты с демонстрационными данными. Референс IMG_1614.PNG не изменён, не добавлен в git/bundle. Макет не подтверждает рендеринг SwiftUI или Liquid Glass на устройстве.

Официальные API: [safeAreaInset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)), [buttonRepeatBehavior](https://developer.apple.com/documentation/swiftui/view/buttonrepeatbehavior(_:)), [KeyEquivalent и keyboardShortcut](https://developer.apple.com/documentation/swiftui/keyequivalent).
