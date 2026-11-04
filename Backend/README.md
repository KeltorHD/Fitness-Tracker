# FitnessTracker Backend

Самостоятельный ASP.NET Core API только для резервных копий WorkoutArchive. Проверяет access JWT Auth Server, хранит архивы и метаданные в PostgreSQL, изолирует их по `sub`.

[HTTP-контракт, лимиты, развёртывание и тесты](../docs/SERVER.md). Пользователи и внешние входы принадлежат проекту Authentication; пароли и refresh tokens в Backend не хранятся.
