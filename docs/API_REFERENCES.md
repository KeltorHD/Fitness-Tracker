# Источники API и конфигурации

Проверено по официальным источникам 2026-10-29. Эти ссылки подтверждают выбор API, но не заменяют type checking и запуск с Apple SDK.

## Liquid Glass

[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) — официальные примеры композиции, namespace, морфинга и порядка модификаторов.

| Использовано | Подтверждённый API / источник |
| --- | --- |
| Контейнер | [`GlassEffectContainer(spacing:content:)`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer), `spacing: CGFloat?`; Apple DocC metadata указывает iOS/iPadOS/watchOS/macOS 26.0+ |
| Эффект | [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), defaults позволяют `.glassEffect()` |
| Идентификатор | [`glassEffectID(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)), Hashable/Sendable ID и `Namespace.ID` |
| Переход | [`glassEffectTransition(_:)`](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)), `.matchedGeometry` внутри контейнера |
| Кнопки | [`glass`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass) и [`glassProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent) |

`Apple/Design/Components.swift` содержит панель действий и таймер. `Apple/Features` и Watch используют нативные button styles. Deployment targets — 26.0, fallback blur и режим совместимости старого дизайна не применяются. Reduce Motion выключает инициируемую приложением morph-анимацию. Визуальные результаты пока не проверены.

## Persistence и Apple-интеграции

- [ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct) — `.none` и `.private(String)`; [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) — ограничения CloudKit-моделей и подготовка schema.
- [HKWorkoutBuilder initializer](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/init(healthstore:configuration:device:)), [beginCollection](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/begincollection(withstart:completion:)), [addWorkoutEvents](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/addworkoutevents(_:completion:)), [finishWorkout](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/finishworkout(completion:)) — применяются async overloads.
- [Activity.request(attributes:content:pushType:)](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:)) — используется `ActivityContent` и локальный режим без push token.
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension) — WidgetKit target; [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) — Lock Screen и Dynamic Island.
- [WCSessionDelegate](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate) — callbacks приходят вне main thread; на iPhone реализованы activation, inactive и deactivate; [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession) — очередь transferUserInfo.
- [Setting up a watchOS project](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project), [WKApplication](https://developer.apple.com/documentation/watchkit/wkapplication), [WKApplication Info.plist key](https://developer.apple.com/documentation/bundleresources/information-property-list/wkapplication) — современный single-target watchOS app и companion configuration.
- [Product.purchase()](https://developer.apple.com/documentation/storekit/product/purchase()), [Transaction.currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements), [Transaction.updates](https://developer.apple.com/documentation/storekit/transaction/updates) — проверка доступа Pro и отзывов.

## XcodeGen, capabilities и privacy

[Официальный Project Spec XcodeGen](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) подтверждает `application`, `app-extension`, `bundle.unit-test`, `bundle.ui-testing`, платформы `iOS`/`watchOS`, local package `path`, `configFiles`, `sources.buildPhase`, `dependencies.embed` и `schemes.run.storeKitConfiguration`. Используется поддерживаемый формат `xcode16_0`, а не предполагаемый `xcode26_0`. Info.plist и entitlements хранятся в репозитории и привязаны документированными Xcode build settings.

Capabilities выражены настоящими entitlement keys: [HealthKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit), [iCloud container identifiers](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-container-identifiers), [iCloud services](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-services), [App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups), [APNs environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment). Регистрация ресурсов и provisioning выполняются на Mac.

[Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) и [Required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) — причины UserDefaults `CA92.1` для собственных настроек и `1C8F.1` для App Group. Manifest явно включён в resources каждого bundle target.

[Swift.org Linux installation](https://www.swift.org/install/linux/) — официальный Swift toolchain; используется версия 6.2.1 для Ubuntu 24.04 x86_64, Swift language mode 6.

## Интерактивная Dynamic Island и фон

- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities): LiveActivityIntent исполняется в app process, определения включаются в app target. `Button(intent:label:)` передаёт заданные параметры; сохранение/обновление должно закончиться до возврата perform.
- [Text timerInterval/pauseTime](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)): системный count-up/countdown и замороженный момент паузы.
- [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app): beginBackgroundTask предоставляет ограниченное время для завершения работы. [Apple DTS notes](https://developer.apple.com/forums/thread/85066/) подтверждают main-thread expiration handler; код освобождает task до возврата из handler.

Оба target используют общий контракт; `FITSESSION_APP` выбирает исполнение с SwiftData только в основном процессе. Подробности проверки: [BACKGROUND_AND_DYNAMIC_ISLAND.md](BACKGROUND_AND_DYNAMIC_ISLAND.md).
