# FitSession

Нативный журнал силовых тренировок: **Swift 6, SwiftUI, iOS 26+, Apple Liquid Glass**.
Разработка ведётся на Linux. Сборка, запуск и проверка Apple-интеграций выполняются на Mac в Xcode.

## Что реализовано

- Свободная тренировка и редактируемые планы; 100 упражнений с русскими названиями и техникой, 200 локальных фотографий, поиск и фильтры, собственные упражнения.
- Вес в кг/фунтах, повторения, разминка, добавление подходов, пауза, отдых, заметки.
- Сохранение каждого изменения, восстановление активной тренировки, история и экспорт JSON.
- Недельный объём, серия тренировочных недель, личные рекорды, оценка 1ПМ.
- Нативная стеклянная панель действий: `GlassEffectContainer`, `glassEffect`, `glassEffectID`, `glassEffectTransition`, стили `glass` / `glassProminent`.
- SwiftData, опциональная системная синхронизация через личный CloudKit container.
- Экспорт завершённой тренировки в HealthKit по запросу, уведомления отдыха.
- Live Activity и Dynamic Island с системными таймерами, следующим подходом и кнопками паузы/продолжения/пропуска отдыха, недельный виджет с добровольной передачей сводки.
- Приложение watchOS: запись подходов, локальное восстановление, надёжная очередь передачи на iPhone с подтверждением сохранения.
- Все функции бесплатны, включая график прогресса за 26 недель.

Это исходники приложения, подготовленные для первой компиляции на Mac. **Успешной iOS/watchOS-сборки ещё не было.** Apple unit/UI tests написаны, но на Linux не запускались. Статусы и ограничения каждого модуля: [IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md).

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

Если `venv` отсутствует, установите пакет `python3-venv`; вместо venv можно использовать системный `python3-yaml`.
Для другого дистрибутива установите подходящий toolchain с [Swift.org](https://www.swift.org/install/linux/).
Проверка не требует сторонних Swift-пакетов и доступа к Apple SDK.

Обычные команды при доступном `swift`:

```bash
swift build
swift test
python3 scripts/validate-project.py
python3 scripts/validate-exercise-library.py
python3 scripts/parse-apple.py
swift format lint --strict --recursive Sources Tests Apple Package.swift
```

`check-linux.sh` перенаправляет кэши в `.build`, собирает пакет, запускает тесты, проверяет ресурсы и выполняет **только синтаксический разбор** Apple-файлов. Это не проверка типов SwiftUI, макросов SwiftData, linking, signing или runtime. GitHub Actions повторяет Linux-проверки.

## Mac

```bash
bash scripts/setup-macos.sh
open FitSession.xcodeproj
```

Понадобятся полный Xcode 26+ с iOS/watchOS 26 SDK и XcodeGen 2.44+. Скрипт устанавливает XcodeGen через имеющийся Homebrew, создаёт локальную конфигурацию, проверяет пакет и выполняет `xcodegen generate`. Signing, Apple Developer resources и первая сборка описаны в [MAC_BUILD_GUIDE.md](MAC_BUILD_GUIDE.md).

## Структура

```text
Package.swift                      # Только Foundation/Core, Swift 6
Sources/FitSessionCore/             # Модели, state machine, расчёты, протоколы
Tests/FitSessionCoreTests/          # Linux/macOS Swift Testing
Apple/App/                         # DI, точка входа, состояние приложения
Apple/Design/                      # Liquid Glass и общие компоненты
Apple/Features/                    # SwiftUI-экраны
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

[Библиотека упражнений](docs/EXERCISE_LIBRARY.md) · [Макеты экранов](docs/previews/README.md) · [Фон и Dynamic Island](docs/BACKGROUND_AND_DYNAMIC_ISLAND.md) · [Архитектура и правила данных](docs/ARCHITECTURE.md) · [Проверенные API](docs/API_REFERENCES.md) · [Проверки на Mac](docs/XCODE_VALIDATION.md)

Основной интерфейс — на русском языке. Нет аналитики, рекламы и сторонних UI-фреймворков. Системные SF Symbols и собственный геометрический значок включены в проект.

Источник упражнений: [free-exercise-db](https://github.com/yuhonas/free-exercise-db), Unlicense; включена подборка 100 записей и сокращённая русская адаптация. Подробности и hashes — в `ThirdParty/free-exercise-db`.
