# FitLife Backend

Самостоятельный ASP.NET Core Backend приложения. Текущий модуль хранит резервные копии WorkoutArchive. Сервер проверяет access JWT Auth Server и отзыв сессии, определяет права локально без прикладных OAuth scopes и изолирует данные по `sub`. БД и пользователь по умолчанию называются `fitnesstracker_backend`, контейнер PostgreSQL — `backend-db`; данные лежат в `.local/backend-db` или по пути из `.env`.

[HTTP-контракт, лимиты, развёртывание и тесты](../docs/SERVER.md). Пользователи и внешние входы принадлежат проекту Authentication; пароли и refresh tokens в Backend не хранятся.
