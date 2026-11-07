# FitnessTracker Authentication

Самостоятельный ASP.NET Core Identity + OpenIddict сервер: Google, Apple, Яндекс, PKCE, refresh tokens и управление аккаунтом. Регистрация и вход по email/паролю и passkey реализованы. Только новые локальные аккаунты требуют подтверждения адреса по ссылке из письма. Отправка — стандартный SMTP (включая Stalwart), настройки `SMTP_*` в `.env`; при выключенном SMTP новые email-регистрации недоступны, прежние аккаунты продолжают входить. Миграция `RequireConfirmationForNewEmailAccounts` сохраняет прежние данные и применяется автоматически при запуске. Подробности и переменные ntfy/SMTP — в [серверной инструкции](../docs/SERVER.md).

[Архитектура, endpoints, провайдеры, migrations и Docker Compose](../docs/SERVER.md). В solution нет зависимости от проекта Backend; удаление копий вызывает его внутренний HTTP endpoint.

Контроллеры содержат только HTTP binding и Mapster mapping; сценарии аккаунта, паролей, passkey, внешних входов, OAuth и AASA выполняют отдельные сервисы. Маппинг задаётся явной DI-конфигурацией, без публикации EF entities и секретных полей.
