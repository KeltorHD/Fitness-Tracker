# Аутентификация и серверные резервные копии

Основа — [согласованная переписка](https://chatgpt.com/share/6aea2280-e498-83eb-be07-a822dfac1c8d): два самостоятельных .NET-приложения, ASP.NET Core Identity + OpenIddict, Google/Apple/Яндекс, PostgreSQL, Docker Compose и Authorization Code + PKCE. Email-вход остаётся следующим этапом: Identity уже поддерживает пароли, но публичных email register/login/reset endpoints пока нет.

## Проекты

| Проект | Назначение |
| --- | --- |
| Существующий `project.yml`, `Apple/`, `Sources/` | Нативное iOS/watchOS-приложение и независимый Swift Core; пути сохранены |
| `Authentication/FitnessTracker.Authentication.csproj` | Пользователи Identity, внешние входы, OAuth/OIDC, сессии, привязки, удаление аккаунта |
| `Backend/FitnessTracker.Backend.csproj` | Только резервные копии; проверка JWT через discovery/JWKS Auth Server |
| `FitnessTracker.Server.sln` | Оба серверных проекта и отдельный тестовый проект `Tests/Server` |

Требуется .NET 10 SDK. Версии пакетов и lock-файлы закреплены. Внутренних ссылок между серверными проектами нет: обмен идёт по HTTP и общему документированному контракту. В production сервисы используют раздельные PostgreSQL-базы и учётные данные. SwiftData остаётся основным локальным хранилищем приложения; сервер не синхронизирует записи и не заменяет CloudKit.

```mermaid
flowchart LR
  iOS[iOS / SwiftUI] -->|PKCE S256| Auth[Authentication / Identity + OpenIddict]
  Auth --> Providers[Apple / Google / Яндекс]
  Auth --> AuthDB[(PostgreSQL: пользователи и токены)]
  iOS -->|JWT / backups scope| API[Backend: резервные копии]
  API --> BackupDB[(PostgreSQL: архивы)]
  API -. discovery / JWKS .-> Auth
  Auth -->|Удаление данных: внутренняя сеть| API
```

## Вход и сессии

Приложение открывает системную `WebAuthenticationSession` из AuthenticationServices. Auth Server показывает русскую страницу выбора доступных провайдеров. OpenIddict Client выполняет и проверяет внешние OAuth/OIDC-потоки, state, nonce и ответ провайдера. Для каждого провайдера используется отдельный callback. Приложение получает одноразовый код на `fitnesstracker://oauth/callback`, проверяет точный URL и state, обменивает код с PKCE S256; client secret в iOS отсутствует. Схема callback уже зарегистрирована приложением. При необходимости можно согласованно перейти на HTTPS callback и Associated Domains; готового AASA для неизвестного домена здесь нет.

iOS использует OAuth access/refresh tokens; профиль получает из защищённого `/v1/account`. ID token не используется как источник identity. Access token действует 10 минут, refresh — до 30 дней с ротацией. Повтор использованного refresh token отвергается и отзывает authorization family; окно повторного использования равно нулю. Параллельные iOS-запросы используют одну операцию обновления; новые токены сначала сохраняются в Keychain. При `invalid_grant` требуется новый вход. Потеря ответа token endpoint может потребовать повторного входа — автоматического повторного обмена использованного refresh нет.

Keychain item изолирован по bundle ID и issuer, не синхронизируется через iCloud, доступен при разблокированном устройстве и не переносится на другое устройство. Сетевой клиент использует HTTPS, тайм-ауты, ephemeral URLSession без cookies/cache и запрещает redirects запросов с credentials. Токены и payloads не логируются. Закрытие экрана отменяет его работу; общая операция ротации принадлежит сессии и сохраняет результат независимо от закрытия одного экрана.

Выход отзывает текущий refresh token. Заблокированный Identity-пользователь не может получить новый authorization code, обменять ранее выданный код, обновить сессию или выполнить новый браузерный вход/привязку. Выданные JWT основного API могут действовать оставшиеся 10 минут: API проверяет их по JWKS без introspection. Для удаления аккаунта действует дополнительная блокировка UUID на стороне Backend, поэтому старый JWT не может создать новую копию удалённого аккаунта.

Аккаунты идентифицируются по паре provider/subject, а не email. Совпадение email не объединяет пользователей. Привязка выполняется на защищённой веб-странице из «Способы входа», с новым provider flow и проверкой текущего пользователя. Нельзя отвязать последний способ входа. Cookie — Secure/HttpOnly; изменяющие веб-формы защищены antiforgery. Email используется только как атрибут внешнего профиля и не считается подтверждённым для будущего password-входа.

## HTTP-контракт

| Сервис / метод | URL | Назначение |
| --- | --- | --- |
| Auth GET | `/.well-known/openid-configuration` | Discovery, включая адрес JWKS |
| Auth GET | `/connect/authorize` | Authorization Code, обязательный PKCE S256, точный зарегистрированный redirect |
| Auth POST | `/connect/token` | Обмен кода / ротация refresh token; form-urlencoded |
| Auth POST | `/connect/revoke` | Стандартный отзыв refresh token; публичный `client_id` |
| Auth GET | `/login` | Выбор включённых провайдеров |
| Auth POST | `/login/{provider}` | Начало внешнего входа / явной привязки; antiforgery |
| Auth GET/POST | `/callback/login/{provider}` | Проверенный OpenIddict callback Google/Apple/Яндекс |
| Auth GET | `/account` | Способы входа и возврат в iOS |
| Auth POST | `/account/unlink/{provider}`, `/account/logout` | Веб-действия с antiforgery |
| Auth GET | `/v1/account` | `{id,name,createdAt,logins}`; bearer token, scope `backups` |
| Auth DELETE | `/v1/account` | Очистка копий, отзыв токенов и удаление Identity-пользователя |
| Backend GET | `/v1/backups` | Массив `{id,createdAt,archiveVersion,size,sha256}` без содержимого копий |
| Backend PUT | `/v1/backups/{uuid}` | UTF-8 архив в body; `application/vnd.fitnesstracker+json` |
| Backend GET | `/v1/backups/{uuid}` | Исходные байты архива, ETag SHA-256 |
| Backend DELETE | `/v1/backups/{uuid}` | Удаление одной собственной копии |
| Backend DELETE | `/internal/users/{uuid}/backups` | Только внутренний service credential; публичный proxy возвращает 404 |
| Оба GET | `/health` | Liveness процесса; не проверка подключения к БД |
| Оба GET, Development | `/openapi/v1.json` | OpenAPI-документ |

Для защищённых API нужен `Authorization: Bearer <access_token>`. Основной API проверяет RS256, тип `at+jwt`, issuer, audience `fitnesstracker-api`, срок, `sub` и scope `backups`. Пользователь не передаёт owner ID в публичном API; все выборки ограничены subject токена. Чужая или отсутствующая копия возвращает одинаковый 404.

PUT создаёт неизменяемую копию: 201 при создании, 200 при повторе тех же байтов и UUID, 409 при попытке заменить содержимое или превышении квоты. iOS сохраняет UUID и байты неудачной загрузки до повтора, чтобы потеря ответа не создавала дубликаты. По умолчанию 10 копий по 20 MiB на аккаунт; старые копии не удаляются автоматически. Некорректный envelope — 400, неподдерживаемый Content-Type — 415, слишком большой body — 413, ограничение частоты — 429. PostgreSQL advisory transaction lock сериализует проверку квоты и удаление аккаунта для одного UUID.

Backend проверяет размер и envelope формата v1–v4, сохраняет JSON как bytea вместе с метаданными в одной транзакции и вычисляет SHA-256. Доменные правила повторно проверяет Swift Core перед импортом. Восстановление сначала проверяет размер/хеш, затем открывает существующий preview импорта: подтверждение обязательно, существующие UUID сохраняются, новые записи добавляются атомарно. Завершённые тренировки не изменяются обходом Core.

Копия содержит тренировки, планы и записи веса тела. Питание, изображения, HealthKit/Bluetooth-пульс, настройки и credentials не входят в существующий WorkoutArchive. Копия создаётся только по явному действию с подтверждением передачи. Она не зашифрована end-to-end: администратор сервера имеет доступ к JSON. Для сервера нужны защищённые диски/volumes и собственная политика хранения резервных копий PostgreSQL.

Удаление аккаунта сначала удаляет bytea-копии и ставит запрет на новые uploads UUID. Если Backend недоступен, Identity-пользователь остаётся и операцию можно повторить. Затем Auth в одной транзакции отзывает и удаляет токены/authorizations, включая зашифрованные session payloads, и удаляет пользователя с привязками. Backend сохраняет только UUID запрета без профиля и содержимого архивов; это защита от старых access tokens. История на iPhone и существующие копии диска/PostgreSQL администратора этим действием не удаляются. Серверные данные аккаунтов с разными UUID никогда не объединяются.

## Подготовка и развёртывание

Нужны Docker Engine + Compose, DNS двух доменов, открытые 80/443 и исходящий HTTPS к провайдерам. Compose использует подсеть `172.30.0.0/24`; если она занята, измените её и доверенный адрес proxy одновременно. Приложения/БД не публикуют порты на хосте.

```bash
bash scripts/setup-server.sh
# Отредактируйте .env: AUTH_DOMAIN, API_DOMAIN, ACME_EMAIL и credentials провайдеров.
docker compose build
docker compose run --rm authentication --migrate
docker compose run --rm backend --migrate
docker compose up -d
```

Скрипт генерирует случайные разные пароли БД, внутренний ключ сервиса, пароль PFX и два RSA-сертификата. Существующие `.env`/ключи он не перезаписывает. `.env`, `.local/`, private keys и сертификаты исключены из git; не добавляйте их принудительно. `.local` доступна только владельцу; PFX в дочерней mount-директории доступны непривилегированному container UID. Исходные `.key` также защищены родительской директорией. Production не использует development/ephemeral keys. Development certificates допустимы только при `ASPNETCORE_ENVIRONMENT=Development`; ephemeral credentials — только в тестовой среде.

Миграции EF Core включены в оба проекта. Изменение схемы делайте новой миграцией; не используйте EnsureDeleted/EnsureCreated для production и не удаляйте volumes при обновлении. `--migrate` Auth также создаёт/обновляет регистрацию iOS client; обычный запуск не меняет схему. Сохраняйте БД Auth, БД Backend, Data Protection volume и сертификаты. Их утрата прервёт существующие сессии. До истечения сертификатов настройте плановую ротацию с перекрытием сроков и публикацией старого публичного ключа на период жизни выданных токенов; автоматическая ротация здесь не реализована. Срок созданных сертификатов — 730 дней.

Caddy выдаёт публичный TLS-сертификат по DNS-доменам; сертификаты PFX выше используются для подписи/шифрования токенов, а не HTTPS. Caddy не ведёт access log с OAuth-кодами. Auth доверяет forwarded headers только указанному proxy. Приватный service key используется исключительно на закрытом HTTP-маршруте Compose-сети; при разнесении сервисов на разные хосты переведите внутренний канал на HTTPS/mTLS.

## Провайдеры

Включайте провайдер только после заполнения его параметров. Отключённые провайдеры не отображаются; без настроенных провайдеров страница честно сообщает о недоступности входа.

| Провайдер | Настройки `.env` | Redirect в кабинете провайдера |
| --- | --- | --- |
| Google | `GOOGLE_ENABLED=true`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`; Web application client | `https://AUTH_DOMAIN/callback/login/google` |
| Яндекс | `YANDEX_ENABLED=true`, `YANDEX_CLIENT_ID`, `YANDEX_CLIENT_SECRET`; доступ к ID/имени и email | `https://AUTH_DOMAIN/callback/login/yandex` |
| Apple | `APPLE_ENABLED=true`, `APPLE_CLIENT_ID` (Services ID), `APPLE_TEAM_ID`, `APPLE_KEY_ID` | `https://AUTH_DOMAIN/callback/login/apple` |

Для Apple зарегистрируйте связанный App ID, Services ID, домен и Return URL в Apple Developer. Поместите скачанный `.p8` в `.local/certificates/apple.p8`, с чтением для container UID; родительскую `.local` оставьте с mode 0700. OpenIddict создаёт client assertion из ключа Apple, provider secrets на iPhone не передаются. Проверка реального входа требует ваших registrations и доступного HTTPS-сервера; тесты их не подменяют заявлениями о готовом production-входе.

## Настройка iOS

Добавьте в существующий `Config/Local.xcconfig`, сохранив прежние Bundle ID/Team:

```xcconfig
FITNESS_TRACKER_AUTH_URL = https:/$()/auth.example.com/
FITNESS_TRACKER_BACKEND_URL = https:/$()/api.example.com/
```

`$()` нужен, чтобы xcconfig не считал `//` началом комментария. Оба значения — корневые HTTPS URL без credentials, query и fragment. Выполните `xcodegen generate`, затем сборку/тесты iOS 26 SDK по MAC_BUILD_GUIDE.md. Серверный экран доступен в «Настройки → Аккаунт и копии». Без конфигурации или при ошибке её чтения локальное приложение продолжает работать. В демо-профиле серверные действия недоступны. Вход/выход не меняет локальную историю и не включает фоновые uploads.

Перед публикацией актуализируйте App Store privacy labels и политику конфиденциальности для добровольной передачи Fitness/Health и данных аккаунта; manifest отражает связанные данные без tracking по [категориям Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype).

## Проверки

Локально 2026-11-04: полный `check-server.sh` прошёл, включая locked restore, сборку без warnings, 71 серверный сценарий и проверку `dotnet format`: 44 unit, 25 функциональных HTTP/Identity/SQLite и 2 интеграционных PostgreSQL 16.6. Новые регрессии подтвердили и исправили обмен токенов заблокированного пользователя и отказ допустимым MIME types в другом регистре. Схема БД и файлы миграций не менялись; существующие миграции проверены на отдельных временных базах обоих сервисов. Ранее проверены Swift-format 6.2.1 strict lint, структура, RU/EN, ресурсы и Compose config. Core build/tests, Apple SDK/XCTest, production images и реальные provider flows не запускались.

```bash
bash scripts/check-server.sh
dotnet tool restore
dotnet ef migrations has-pending-model-changes --project Authentication
dotnet ef migrations has-pending-model-changes --project Backend
```

Наборы находятся в одном xUnit-проекте; категории позволяют запускать их отдельно:

| Категория | Исходники | Что проверяется |
| --- | --- | --- |
| `Unit` | `Tests/Server/BackupArchiveValidatorTests.cs` | v1–v4 и legacy format, обязательные поля, неверные JSON-типы/UTF-8, точные границы байтов и количества записей, безопасные ошибки; без БД и HTTP |
| `Unit` | `Tests/Server/BackupCleanupTests.cs` | DELETE/service key контракт, ошибки статуса и конфигурации, передача отмены в HTTP handler без сети |
| `HTTP` | `Tests/Server/BackendTests.cs` | JWT/subject/scope и изоляция пользователей, MIME type, SHA-256/headers/фиксированное время, квота, идемпотентность, откат при отказе/отмене записи |
| `HTTP` | `Tests/Server/AuthenticationTests.cs` | PKCE, code/refresh/revoke, блокировка аккаунта, scopes, prompt=none, antiforgery, внешние привязки и удаление данных |
| `PostgreSQL` | `Tests/Server/PostgresTests.cs` | Раздельные БД Auth/Backend, существующие миграции и model snapshots, конкурентная квота, гонка PUT/удаления и сохранность чужих данных |

```bash
dotnet test FitnessTracker.Server.sln --no-build --no-restore -m:1 --filter 'Category=Unit'
dotnet test FitnessTracker.Server.sln --no-build --no-restore -m:1 --filter 'Category=HTTP'
```

Обычный прогон не вызывает внешних OAuth-провайдеров. HTTP fixtures используют настоящий in-memory host и собственную SQLite, очищают пользовательские configuration sources, явно отключают внешние providers и внедряют фиксированное время для метаданных. Отказ/отмена SaveChanges подменяются через EF interceptor, сохраняя настоящую транзакцию и проверки результата. Сценарии и вспомогательные классы имеют XML-описания на русском языке.

Для PostgreSQL задайте `FITNESS_TRACKER_TEST_POSTGRES` connection string к **одноразовому тестовому экземпляру** и запустите `check-server.sh`; он включит обе PostgreSQL-проверки. Только эту категорию запускают с `--filter 'Category=PostgreSQL'`. Без явной конфигурации прямой запуск категории завершается ошибкой, а не молчаливым пропуском. Fixture создаёт случайные отдельные базы с отключённым pooling и удаляет только их с отдельным cleanup deadline, включая сбой основного теста. CI поднимает PostgreSQL 18; локально проверено на 16.6, на динамически выделенном localhost-порту. Файлы миграций для этих тестов не генерируются и не изменяются.

Apple XCTest `AccountBackupTests` проверяют callback validation, одну ротацию для параллельных запросов, ошибки сети/Keychain, истёкшую сессию и проверку целостности; `ArchiveTransferTests` проверяет подтверждение восстановления. Их запуск требует Xcode. Foundation-часть добавлена в Swift 6 type-check скрипта `check-linux.sh`; SwiftUI/Keychain/CryptoKit и реальный вход требуют Apple SDK/устройства. Чек-лист: [XCODE_VALIDATION.md](XCODE_VALIDATION.md).

Официальные источники: [OpenIddict ASP.NET Core](https://documentation.openiddict.com/integrations/aspnet-core), [Web providers](https://documentation.openiddict.com/integrations/web-providers), [пример Velusia](https://github.com/openiddict/openiddict-samples/tree/dev/samples/Velusia), [Apple WebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/webauthenticationsession), [Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect), [Яндекс ID](https://yandex.ru/dev/id/doc/ru/), [Sign in with Apple](https://developer.apple.com/documentation/signinwithapplerestapi).
