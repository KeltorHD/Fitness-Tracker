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

## Интерактивная панель навигации

Выделение вкладки использует glassEffectID/glassEffectTransition из раздела Liquid Glass выше. CGRect кнопок измеряются официальным [onGeometryChange(for:of:action:)](https://developer.apple.com/documentation/swiftui/view/ongeometrychange(for:of:action:)); [highPriorityGesture(_:including:)](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:)) отделяет drag от обычного нажатия кнопки. Это собственный SwiftUI-контрол с настоящим стеклом; идентичность поведения системному TabView не заявляется. Проверка рендеринга/жестов требует Xcode.

## Persistence и Apple-интеграции

- [ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct) — `.none` и `.private(String)`; [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) — ограничения CloudKit-моделей и подготовка schema.
- [HKWorkoutBuilder initializer](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/init(healthstore:configuration:device:)), [beginCollection](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/begincollection(withstart:completion:)), [addWorkoutEvents](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/addworkoutevents(_:completion:)), [finishWorkout](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/finishworkout(completion:)) — применяются async overloads.
- [Activity.request(attributes:content:pushType:)](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:)) — используется `ActivityContent` и локальный режим без push token.
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension) — WidgetKit target; [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) — Lock Screen и Dynamic Island.
- [WCSessionDelegate](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate) — callbacks приходят вне main thread; на iPhone реализованы activation, inactive и deactivate; [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession) — очередь transferUserInfo.
- [Setting up a watchOS project](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project), [WKApplication](https://developer.apple.com/documentation/watchkit/wkapplication), [WKApplication Info.plist key](https://developer.apple.com/documentation/bundleresources/information-property-list/wkapplication) — современный single-target watchOS app и companion configuration.

## XcodeGen, capabilities и privacy

[Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios) — матрица программ: iCloud/Push недоступны бесплатному Apple Developer account; HealthKit и App Groups отмечены доступными. По ней подготовлена отдельная схема FitLife Personal; runtime/signing на Personal Team ещё требуют проверки в Xcode.

[Официальный Project Spec XcodeGen](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) подтверждает `application`, `app-extension`, `bundle.unit-test`, `bundle.ui-testing`, платформы `iOS`/`watchOS`, local package `path`, `configFiles`, `sources.buildPhase`, `dependencies.embed`. Используется поддерживаемый формат `xcode16_0`, а не предполагаемый `xcode26_0`. Info.plist и entitlements хранятся в репозитории и привязаны документированными Xcode build settings.

Capabilities выражены настоящими entitlement keys: [HealthKit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit), [iCloud container identifiers](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-container-identifiers), [iCloud services](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-services), [App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups), [APNs environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment). Регистрация ресурсов и provisioning выполняются на Mac.

[Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) и [Required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) — причины UserDefaults `CA92.1` для собственных настроек и `1C8F.1` для App Group. Manifest явно включён в resources каждого bundle target.

[Swift.org Linux installation](https://www.swift.org/install/linux/) — официальный Swift toolchain; используется версия 6.2.1 для Ubuntu 24.04 x86_64, Swift language mode 6.

## Интерактивная Dynamic Island и фон

- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities): LiveActivityIntent исполняется в app process, определения включаются в app target. `Button(intent:label:)` передаёт заданные параметры; сохранение/обновление должно закончиться до возврата perform.
- [Text timerInterval/pauseTime](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)): системный count-up/countdown и замороженный момент паузы.
- [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app): beginBackgroundTask предоставляет ограниченное время для завершения работы. [Apple DTS notes](https://developer.apple.com/forums/thread/85066/) подтверждают main-thread expiration handler; код освобождает task до возврата из handler.

Оба target используют общий контракт; `FITLIFE_APP` выбирает исполнение с SwiftData только в основном процессе. Подробности проверки: [BACKGROUND_AND_DYNAMIC_ISLAND.md](BACKGROUND_AND_DYNAMIC_ISLAND.md).

[Swift 6.2 nonisolated async / @concurrent](https://docs.swift.org/latest/documentation/diagnostics/nonisolated-nonsending-by-default/) — @concurrent явно выбирает generic executor. LiveActivityService передаёт только IDs и WorkoutLiveState; end/update получают SDK handle внутри nonisolated helper и не отправляют Activity из MainActor. Никакие @unchecked Sendable/@preconcurrency или отключения diagnostics не добавлены; Apple SDK compilation проверяется отдельно на Mac.

## JSON / .fitlife

- [fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)) — системный single-file picker; доступ к URL балансируется startAccessingSecurityScopedResource/stopAccessingSecurityScopedResource.
- [fileExporter для Transferable](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:item:contenttypes:defaultfilename:oncompletion:oncancellation:)) — параметр item, contentTypes, defaultFilename и отдельная отмена; официальный DocC указывает iOS 17+, подходит iOS 26 target.
- [exportingCondition](https://developer.apple.com/documentation/coretransferable/transferrepresentation/exportingcondition(_:)) — `@Sendable (Self.Item) -> Bool`, iOS 16+. Ограничивает representation выбранным JSON/FitLife, поскольку пользовательский UTI сам conforms to JSON.
- [Defining file and data types](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app), [CFBundleDocumentTypes](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes), [LSSupportsOpeningDocumentsInPlace](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsopeningdocumentsinplace) — UTI com.fitlife.archive, расширение fitlife, JSON conformance, Viewer/Owner и отдельный JSON Alternate.
- [NSFileCoordinator coordinated read](https://developer.apple.com/documentation/foundation/nsfilecoordinator/coordinate(readingitemat:options:error:byaccessor:)) — синхронное coordinated чтение на worker actor, используется переданный accessor URL. Данные ограничиваются до 20 МиБ. Отмена проверяется перед/после coordination и между блоками чтения; ожидание file provider может завершиться позже отмены UI.

Новые document APIs iOS 27 не требуются. File association и фактическое поведение диалогов остаются в Xcode validation checklist.

## Удаление свайпом и техника упражнения

Штатные [swipeActions(edge:allowsFullSwipe:content:)](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:)) размещены на строках List; `allowsFullSwipe: false` раскрывает действие без автоматического выполнения. Навигация к технике карточки использует [navigationDestination(item:destination:)](https://developer.apple.com/documentation/swiftui/view/navigationdestination(item:destination:)) на стабильном корне экрана, вне ленивых строк. SwipeActionsContainer требует iOS 27 по Apple DocC metadata и не используется при deployment iOS 26. Проверка native gestures/SDK остаётся за Xcode.


## Питание: Open Food Facts и системный выбор фото

Проверено по документации 2026-11-03:

- [Open Food Facts API introduction](https://openfoodfacts.github.io/openfoodfacts-server/api/): read без ключа, User-Agent, ограничения запросов; полнотекстовый legacy `cgi/search.pl`, чтение продукта `/api/v2/product/{code}.json`. В приложении явный поиск, максимум 24 результата, timeout 20 s, локальный лимит 8 запросов/минуту, без автоматических retries. Для массовой нагрузки нужен собственный индекс/экспорты и согласование использования с OFF; полный dump не входит в приложение.
- [OFF licenses](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/): база ODbL 1.0, отдельное содержимое DbCL, изображения CC BY-SA; в приложении attribution, ссылки на лицензии и исходный продукт. Фото из FatSecret не используются. OFF не является полной базой всех продуктов; неизвестные значения не заменяются нулями. Используются snapshot КБЖУ и источник, чтобы изменение каталога не переписало историю пользователя.
- [OFF product nutrition schema](https://github.com/openfoodfacts/openfoodfacts-server/blob/main/docs/api/ref/schemas/product_nutrition.yaml): поля с суффиксом `_100g` могут относиться к 100 мл. Единицы определяются по quantity unit, nutrition basis и serving size, видны пользователю и могут быть сверены/изменены по упаковке. Масса и объём не пересчитываются без плотности. Энергия берётся из kcal либо из kJ / 4.184; рассчитывать КБЖУ по фотографии приложение не пытается.
- [FatSecret logging options](https://www.fatsecret.com/fatsecret-app-help/getting-started/food-add-options): ориентир для сценариев выбора продукта, размера порции, recent foods и saved meals. Это самостоятельная реализация: нет копирования закрытой базы, брендинга, платных функций/подписок. Голосовой помощник, AI-распознавание, сообщество, планировщик и каталог рецептов FatSecret не реализованы.
- [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker), [loadTransferable](https://developer.apple.com/documentation/photosui/photospickeritem/loadtransferable(type:)), [CGImageSourceCreateThumbnailAtIndex](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)): системный выбор существующего фото, передача Data, resize/re-encode на worker actor. Широкий доступ к медиатеке и camera permission не запрашиваются. Фотографию можно предварительно сделать системной камерой; встроенная съёмка не добавлена.

Nutrition payload version 1 хранится в новых kinds `foodEntry` / `nutritionGoal` существующего StoredRecord (schemaVersion 1), старые kinds/UUID и WorkoutArchive v4 не меняются. JPEG до 600 KB хранится в агрегате для атомарного сохранения вместе с записью; экспорт архива тренировок явно не включает питание. Core и portable проверки работают offline; настоящие OFF ответы, Apple SDK, PhotosPicker, SwiftData/CloudKit и UI требуют отдельной проверки на Mac.


## Оформление и системная динамика Live Activity

Проверено по документации Apple 2026-11-03:

- [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities): компактная структура, системные границы, ContainerRelativeShape для согласованных отступов/скруглений и акцент keyline. На Lock Screen нужно проверять высоту; [ActivityKit presentation](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) предупреждает об обрезке выше 160 pt.
- [ActivityConfiguration init](https://developer.apple.com/documentation/widgetkit/activityconfiguration/init(for:content:dynamicisland:)): content — ViewBuilder, dynamicIsland — обычное замыкание, возвращающее DynamicIsland. После локальной переменной темы используется явный return.
- [ProgressView(timerInterval:countsDown:)](https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:)): системный прогресс по сохранённому диапазону дат; countsDown=true уменьшает заполнение. Он не требует polling и не использует custom progress style.
- [Animating data updates](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities): краткие переходы при обновлении данных; учтены Reduce Motion и isLuminanceReduced. Постоянные анимации/фоновые циклы не добавлены.
