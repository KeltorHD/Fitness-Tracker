# FitLife

Нативный журнал силовых тренировок: **Swift 6, SwiftUI, iOS 26+, Apple Liquid Glass**.
Разработка ведётся на Linux. Сборка, запуск и проверка Apple-интеграций выполняются на Mac в Xcode.

Для FitLife выполните `xcodegen generate`, откройте **FitLife.xcodeproj** и выберите **FitLife Personal**. Настройки используют только `FITLIFE_*`; прежние identifiers, архивы и aliases не поддерживаются. [Текущие идентификаторы и развёртывание](docs/RENAME.md).

## Что реализовано

- Свободная тренировка и редактируемые планы; 876 упражнений с русскими названиями, разметкой мышц и доступной в источнике техникой, 1746 локальных фотографий, поиск и фильтры по схеме тела, собственные упражнения.
- Компактный список упражнений и карточка подходов: небольшие поля с предыдущими значениями, замена числа при первом вводе, заметки через контекстное меню и свайп, переключение упражнений, техника и графики. [Превью тренировки](docs/previews/workout-flow.png), [превью пульса](docs/previews/heart-rate-overview.png) — демонстрационные макеты.
- Вес в кг/фунтах, повторения, разминка, добавление подходов, пауза, отдых, заметки.
- Цифровая панель по нажатию на вес/повторы: замена значения, переход к следующему полю, копирование вниз и скрытие. [Превью](docs/previews/number-entry-overview.png), [поведение](docs/NUMBER_ENTRY.md).
- Разминка и дропсеты с 1–5 снижениями веса: последовательная запись, отдых после последнего этапа, точный объём, повтор и архив v4. [Правила](docs/DROP_SETS.md), [демо-макет](docs/previews/workout-set-types.png).
- Сохранение выполненных подходов и изменений, восстановление активной тренировки, недельный дневник, повтор завершённой тренировки.
- Импорт и экспорт JSON / `.fitlife`: отдельная тренировка или вся история с планами, открытие из «Файлов», сводка перед импортом и защита от повторных записей.
- Недельный объём, серия тренировочных недель, личные рекорды, оценка 1ПМ.
- Пять графиков по упражнению: рабочий вес, объём, 1ПМ, повторения и подходы; выбор периода и точки. Переход **Прогресс упражнения** из активной тренировки и её истории. [Расчёты и сценарии](docs/EXERCISE_PROGRESS.md).
- **Вес тела**: текущий вес в настройках и верхней сводке активной тренировки, автоподстановка в новые сессии; взвешивания и история в результатах. Кг/фунты, JSON-архивы и изоляция демо. [Правила хранения](docs/BODY_WEIGHT.md).
- Нативная стеклянная панель действий: `GlassEffectContainer`, `glassEffect`, `glassEffectID`, `glassEffectTransition`, стили `glass` / `glassProminent`.
- SwiftData, опциональная системная синхронизация через личный CloudKit container.
- Экспорт завершённой тренировки в HealthKit по запросу, уведомления отдыха.
- Live Activity и Dynamic Island с системными таймерами, следующим подходом и кнопками паузы/продолжения/пропуска отдыха, недельный виджет с добровольной передачей сводки.
- Приложение watchOS: запись подходов, локальное восстановление, надёжная очередь передачи на iPhone с подтверждением сохранения.
- Все функции бесплатны, включая график прогресса за 26 недель.
- Два режима фитнес-трекера: показатели из Apple «Здоровье» (Mi Fitness → Health) и Bluetooth-пульс во время тренировки, локальная запись и график в истории.
- Пульс AirPods Pro 3 через системную сессию HealthKit: явное включение в тренировке, пауза/продолжение, локальная запись и график. [Подключение и границы проверки](docs/AIRPODS.md).
- Русский и английский интерфейс, выбор языка в настройках; каталог упражнений и инструкции доступны на обоих языках офлайн.
- Демо-профиль: **Настройки → Демонстрационные данные → Открыть демо-профиль**. 24 тренировки за восемь недель и три плана, отдельно от личной истории; перезагрузка данных и возврат в свой профиль. [Подробности](docs/DEMO_DATA.md).

Это исходники приложения, подготовленные для первой компиляции на Mac. **Успешной iOS/watchOS-сборки ещё не было.** Apple unit/UI tests написаны, но на Linux не запускались. Статусы и ограничения каждого модуля: [IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md).

Импорт CSV из FitSession доступен в **Настройки → Данные → Импорт и экспорт**: оба варианта заголовка пропущенных подходов, множители веса, заметки и защита от повторного импорта. [Формат и ограничения](docs/CSV_IMPORT.md).

## Linux

Текущая проверенная среда: Ubuntu 24.04 x86_64, официальный Swift 6.2.1. Установка без `sudo`:

```bash
bash scripts/setup-linux.sh
# Выполните напечатанную команду export PATH, либо скрипт проверки найдёт локальный toolchain.
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install -r requirements-dev.txt
bash scripts/check-linux.sh
```

Если `venv` отсутствует, установите пакет `python3-venv`; вместо venv можно использовать системные пакеты `python3-yaml` и `python3-pil`.
Для другого дистрибутива установите подходящий toolchain с [Swift.org](https://www.swift.org/install/linux/).
Проверка не требует сторонних Swift-пакетов и доступа к Apple SDK.

Обычные команды при доступном `swift`:

```bash
swift build
swift test
python3 scripts/validate-project.py
python3 scripts/validate-exercise-library.py
python3 scripts/validate-localizations.py
python3 scripts/parse-apple.py
swift format lint --strict --recursive Sources Tests Apple Package.swift
```

`check-linux.sh` перенаправляет кэши в `.build`, собирает пакет, запускает тесты, проверяет ресурсы и синтаксис Apple-файлов. Переносимые модели дневника/результатов/поиска, файловый сервис и контракты дополнительно проходят Swift 6 type-check без Apple SDK; явный список находится в скрипте. Это не проверка типов SwiftUI, макросов SwiftData, linking, signing или runtime. GitHub Actions повторяет Linux-проверки.

## Mac

```bash
bash scripts/setup-macos.sh
open FitLife.xcodeproj
```

Понадобятся полный Xcode 26+ с iOS/watchOS 26 SDK и XcodeGen 2.44+. Скрипт устанавливает XcodeGen через имеющийся Homebrew, создаёт локальную конфигурацию, проверяет пакет и выполняет `xcodegen generate`. Signing, Apple Developer resources и первая сборка описаны в [MAC_BUILD_GUIDE.md](MAC_BUILD_GUIDE.md).

Для бесплатной **Personal Team** выберите схему **FitLife Personal**: iCloud/Push отключены, история хранится локально. Полная схема **FitLife** сохраняет эти capabilities для Apple Developer Program. Укажите свою Team во вложенных targets и уникальный Bundle ID в Config/Local.xcconfig; не оставляйте `com.yourcompany.fitlife`.

## Структура

```text
Package.swift                      # Только Foundation/Core, Swift 6
Sources/FitLifeCore/             # Модели, state machine, расчёты, протоколы
Tests/FitLifeCoreTests/          # Linux/macOS Swift Testing
Tests/PortableTrackerChecks/        # Исполняемые проверки Foundation/Observation с fakes
Apple/App/                         # DI, точка входа, состояние приложения
Apple/Design/                      # Liquid Glass и общие компоненты
Apple/Features/                    # SwiftUI-экраны и presentation models
Apple/Persistence/                 # SwiftData repository
Apple/Services/                    # HealthKit, CloudKit, ActivityKit, WCSession
Apple/Shared/                      # Контракт Live Activity и сводка виджета
Apple/Widgets/                     # WidgetKit extension + Dynamic Island
Apple/Watch/                       # Отдельное приложение watchOS
Apple/Tests/                       # iOS unit tests
Apple/UITests/                     # XCTest UI flows
Config/                            # Info.plist, entitlements, xcconfig
Resources/                         # iOS/watchOS assets, privacy manifest
project.yml                        # XcodeGen, пять targets
scripts/                           # Установка, валидация и Linux-проверки
```

[Библиотека упражнений](docs/EXERCISE_LIBRARY.md) · [Дизайн по референсам](docs/REFERENCE_DESIGN.md) · [Макеты экранов](docs/previews/README.md) · [Фон и Dynamic Island](docs/BACKGROUND_AND_DYNAMIC_ISLAND.md) · [Архитектура и правила данных](docs/ARCHITECTURE.md) · [Проверенные API](docs/API_REFERENCES.md) · [Проверки на Mac](docs/XCODE_VALIDATION.md)

Импорт/экспорт: **Настройки → Данные → Импорт и экспорт**; для одной тренировки — **меню карточки → Экспорт файла**. [Формат и правила переноса](docs/IMPORT_EXPORT.md).

Язык: **Настройки → Основные → Язык приложения** — «Как на устройстве», «Русский» или «English». Смена применяется сразу; названия ваших тренировок, планов и заметки сохраняются. Интерфейс, каталог, виджеты и Live Activity используют RU/EN; системные диалоги следуют настройкам iOS. [Устройство локализации и проверка](docs/LOCALIZATION.md).

Нет аналитики, рекламы и сторонних UI-фреймворков. Системные SF Symbols и собственный геометрический значок включены в проект.

Источник упражнений: [free-exercise-db](https://github.com/yuhonas/free-exercise-db), Unlicense; включена подборка 100 записей и сокращённая русская адаптация. Подробности и hashes — в `ThirdParty/free-exercise-db`.

Главные разделы: Дневник, Каталог, Результаты и Настройки. Оформление переработано по 11 скриншотам пользователя; окружности и фотопрогресс из исходного приложения пока не реализованы.

Фитнес-трекер: **Настройки → Основные → Трекер**. В выборе модели есть Mi Band 10 и HUAWEI WATCH GT 6 Pro: инструкции для Mi Fitness/HUAWEI Health → «Здоровье» и Share HR/HR Data Broadcasts по Bluetooth. [Подключение и ограничения](docs/MI_BAND.md). Оба режима требуют проверки на реальном iPhone; совместимость с конкретным браслетом на Linux не проверялась.

Графики: **Результаты → Пульс и шаги**. Включите чтение пульса и шагов из «Здоровья»: доступны пульс за выбранный день, шаги за семь дней до него включительно и последнее измерение с временем и источником. Во время тренировки текущий пульс и график видны в обзоре и упражнении. Apple Watch и приложения браслетов передают данные через «Здоровье» с возможной задержкой; для прямого приёма используйте поддерживаемый Bluetooth-пульсометр или существующий режим AirPods Pro 3. Новые SDK-запросы и UI требуют проверки на iPhone.
## Серверные проекты

Рядом с существующим iOS-проектом добавлены [Authentication](Authentication/README.md) и [Backend](Backend/README.md) на .NET 10. Первый отвечает за аккаунты и вход через email/пароль, passkey и Google/Apple/Яндекс, второй — только за добровольные резервные копии. Настройка, Docker Compose, существующий Nginx на хосте с вашими TLS-сертификатами и API описаны в [docs/SERVER.md](docs/SERVER.md). Локальный журнал работает без аккаунта. Новые email-аккаунты требуют подтверждения по ссылке через настраиваемый SMTP; прежние аккаунты сохраняют доступ.

Команда `python3 scripts/setup-server-network.py` подготавливает автоматически выбранную Docker-сеть и локальный конфиг Nginx. Auth и Backend применяют включённые миграции при обычном запуске, до приёма запросов. Базы, ключи и сертификаты по умолчанию хранятся в `.local/` рядом с проектом; пути переопределяются в `.env`. Backend определяет права на свои функции самостоятельно, без прикладных OAuth scopes. Ненастроенные внешние способы входа видны серыми с подсказкой «В разработке».
