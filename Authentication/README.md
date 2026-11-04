# FitnessTracker Authentication

Самостоятельный ASP.NET Core Identity + OpenIddict сервер: Google, Apple, Яндекс, PKCE, refresh tokens и управление аккаунтом. Регистрация и вход по email/паролю без подтверждения почты, а также passkey реализованы. Миграция AddPasskeys включена в проект; применяйте миграции перед обновлением сервера, подробности в серверной инструкции.

[Архитектура, endpoints, провайдеры, migrations и Docker Compose](../docs/SERVER.md). В solution нет зависимости от проекта Backend; удаление копий вызывает его внутренний HTTP endpoint.
