# Русский и английский

Выбор: **Настройки → Основные → Язык приложения** — «Как на устройстве», «Русский», «English». Язык сохраняется в UserDefaults, SwiftUI получает новую locale без пересоздания AppStore и сброса навигации. Системный режим выбирает первый поддерживаемый язык из предпочтений устройства; при отсутствии RU/EN используется английский. Региональные настройки чисел, десятичного разделителя, часового пояса и начала недели сохраняются.

## Что переводится

- Четыре вкладки, активная тренировка, история, планы, статистика и настройки.
- Подписи, ошибки приложения, пустые состояния, accessibility labels, импорт/экспорт.
- Два режима трекера, сводка «Здоровья», Bluetooth-подключение, профили Mi Band/HUAWEI WATCH GT 6 Pro и график пульса.
- Названия, мышцы, инвентарь и инструкции 100 упражнений; оба каталога работают офлайн с теми же UUID и фотографиями.
- Уведомления отдыха при планировании; смена языка перепланирует текущий отдых через существующий integration coordinator.
- Недельный виджет получает только языковое предпочтение через App Group. Передача числа тренировок по-прежнему требует отдельного opt-in.
- Live Activity/Dynamic Island получает язык и локализованное имя следующего упражнения в display snapshot. Поле языка optional: старые snapshots продолжают декодироваться.
- Watch использует RU/EN по языку часов. Он не получает настройку языка iPhone через WatchConnectivity.

Пользовательские названия, заметки и техника собственных упражнений не переводятся автоматически. История и шаблоны, включая ранее созданные стартовые планы, не переименовываются. В архиве остаются исходные пользовательские строки и стабильные IDs.

Системные диалоги Files/HealthKit, разрешения и метаданные App Intents/конфигурации виджета используют системный или назначенный в iOS язык приложения. Внутренний переключатель меняет интерфейс FitnessTracker, но не настройки iOS. Для HealthKit включён отдельный InfoPlist.xcstrings. Лицензия и собственные названия источников остаются в оригинале.

## Ресурсы и изменения переводов

`Resources/Localizable.xcstrings` — нативный String Catalog с 503 ключами RU/EN, включая демо-профиль, общий для iOS, widgets и Watch. `Resources/InfoPlist.xcstrings` — четыре строки главного приложения. Xcode компилирует их в `.lproj` resources. `L10n` читает обычные локализованные bundles; подмены Bundle и глобального изменяемого состояния нет. Для динамических строк Core сохраняет прежние русские error descriptions, а Apple presentation переводит их перед показом.

Исходники переводов интерфейса — `Data/Localization/Interface.en.json` и RU overrides в `Interface.ru.json`. Новая русская строка обычно служит ключом; форматированные сообщения принимают String-аргументы `%@`. Для счётчиков используются явные формы `one/few/many/other`, выбранные проверенными правилами AppLanguage. При добавлении языка нужны его правила и все переводы.

```bash
python3 scripts/generate-localizations.py
python3 scripts/validate-localizations.py
```

Переводы упражнений поддерживаются отдельно в `Data/ExerciseLibrary/*.tsv`; английский каталог воспроизводится из закреплённого лицензированного источника командой `python3 scripts/import-exercise-library.py`. Сеть не требуется.

## Проверки

**Implemented:** RU/EN ресурсы, выбор языка, lookup, plurals, все перечисленные экраны и расширения.

**Linux-tested:** Core language resolution/регион/plurals, identity каталогов и двуязычный поиск, обратная совместимость Live State; проверены placeholders, полнота русских ключей в Apple/Core, target membership и повторяемость генерации. L10n и форматирование длительности прошли Swift 6 strict-concurrency type-check с Foundation без Apple SDK.

**Requires Xcode validation:** реальная компиляция String Catalog, SwiftUI, переключение/сохранение выбора, системные языки, расширения и permissions. Написаны L10nTests, тест изоляции языковой настройки виджета и UI-тест переключения; они не запускались на Linux. Сценарии: [XCODE_VALIDATION.md](XCODE_VALIDATION.md).

**Requires Apple Developer configuration:** для самой локализации не требуется; виджет использует существующий App Group, интеграции — свои capabilities.

Основа: [Apple String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog), [Bundle.localizedString](https://developer.apple.com/documentation/foundation/bundle/localizedstring(forkey:value:table:)).
