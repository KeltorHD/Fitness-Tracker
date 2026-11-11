#!/usr/bin/env python3
"""Создаёт отдельный сертификат шифрования Backend, сохраняя существующие ключи и .env."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def run(arguments, root, environment):
    """Запускает команду без shell и без публикации вывода с секретами."""
    result = subprocess.run(arguments, cwd=root, env=environment, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError("Не удалось подготовить сертификат Backend. Проверьте Compose, пути и CERTIFICATE_PASSWORD; существующие ключи не заменяются.")
    return result.stdout


def prepare(root):
    """Подготавливает PFX по настройкам Compose; повторный запуск проверяет его без перезаписи."""
    if not (root / ".env").is_file():
        raise RuntimeError("Сначала создайте .env через bash scripts/setup-server.sh.")
    # Только чтение config: gateway ещё может отсутствовать при первой подготовке.
    environment = dict(os.environ, SERVER_NETWORK_GATEWAY="127.0.0.1")
    config = json.loads(run(["docker", "compose", "config", "--format", "json"], root, environment))
    backend = config["services"]["backend"]
    mounts = [mount for mount in backend["volumes"] if mount["target"] == "/run/certificates" and mount["type"] == "bind"]
    if len(mounts) != 1 or backend["environment"]["Certificates__Encryption__Path"] != "/run/certificates/encryption.pfx":
        raise RuntimeError("Ожидался bind mount /run/certificates и файл encryption.pfx.")
    directory = Path(mounts[0]["source"])
    target = directory / "encryption.pfx"
    password = backend["environment"]["Certificates__Encryption__Password"]
    if not password:
        raise RuntimeError("CERTIFICATE_PASSWORD не должен быть пустым.")
    environment["FITNESS_TRACKER_BACKEND_CERTIFICATE_PASSWORD"] = password
    if target.exists():
        run(["openssl", "pkcs12", "-in", str(target), "-passin", "env:FITNESS_TRACKER_BACKEND_CERTIFICATE_PASSWORD", "-noout"], root, environment)
        print("Существующий сертификат Backend проверен; ключи и .env сохранены.")
        return
    (root / ".local").mkdir(mode=0o700, exist_ok=True)
    created_directory = not directory.exists()
    directory.mkdir(mode=0o755, parents=True, exist_ok=True)
    # setup-server.sh использует umask 077; mount должен читаться runtime UID.
    if created_directory:
        directory.chmod(0o755)
    with tempfile.TemporaryDirectory(prefix=".backend-certificate-", dir=directory) as temporary:
        files = Path(temporary)
        run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256", "-nodes", "-days", "730",
             "-subj", "/CN=FitLife Backend encryption", "-keyout", str(files / "key.pem"),
             "-out", str(files / "certificate.pem")], root, environment)
        run(["openssl", "pkcs12", "-export", "-inkey", str(files / "key.pem"), "-in", str(files / "certificate.pem"),
             "-out", str(files / "encryption.pfx"), "-passout", "env:FITNESS_TRACKER_BACKEND_CERTIFICATE_PASSWORD"], root, environment)
        # Публикуем готовый PFX атомарно в пределах одной файловой системы.
        # link не заменит ключ, созданный другим параллельным запуском.
        generated = files / "encryption.pfx"
        generated.chmod(0o444)
        os.link(generated, target)
    print("Отдельный сертификат шифрования Backend создан; ключи Auth и .env сохранены.")


if __name__ == "__main__":
    try:
        prepare(Path(__file__).resolve().parent.parent)
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        message = str(error) if isinstance(error, RuntimeError) else "Не удалось подготовить сертификат Backend; существующие ключи не перезаписывались."
        print(message, file=sys.stderr)
        sys.exit(1)
