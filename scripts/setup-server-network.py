#!/usr/bin/env python3
"""Подготавливает Docker bridge и согласованные настройки Auth, Backend и Nginx."""

import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


PROJECT_LABEL = "com.fitlife.project"


def docker(root, *arguments, environment=None, check=True):
    """Вызывает Docker без shell и без вывода конфигурации с секретами."""
    result = subprocess.run(
        ["docker", *arguments], cwd=root, env=environment,
        capture_output=True, text=True, timeout=30,
    )
    if check and result.returncode:
        raise RuntimeError(
            f"Не удалось выполнить docker {' '.join(arguments[:2])}. "
            "Проверьте доступ к Docker, docker compose config --quiet и COMPOSE_FILE "
            "(на Linux файлы разделяются двоеточием). "
            "При ошибке создания сети проверьте свободные address pools Docker."
        )
    return result


def upstream(config, service):
    """Извлекает проверенные домен и loopback-порт для Nginx из Compose."""
    settings = config["services"][service]
    host = settings["environment"]["AllowedHosts"].split(";")[0]
    labels = host.split(".")
    if len(host) > 253 or len(labels) < 2 or not all(
        re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
        for label in labels
    ):
        raise RuntimeError("AUTH_DOMAIN/API_DOMAIN должны содержать только DNS-имя.")
    ports = settings.get("ports", [])
    if len(ports) != 1 or ports[0].get("host_ip") != "127.0.0.1" or ports[0]["target"] != 8080:
        raise RuntimeError("HTTP upstream должен публиковаться только на 127.0.0.1.")
    port = int(ports[0]["published"])
    if not 1 <= port <= 65535:
        raise RuntimeError("Некорректный HTTP-порт.")
    return host, port


def atomic_write(path, content):
    """Атомарно записывает локальную конфигурацию с доступом только владельцу."""
    if path.is_symlink():
        raise RuntimeError(f"Ожидался обычный файл: {path.name}.")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def prepare(root):
    """Создаёт или повторно использует сеть, сохраняя остальные настройки и ключи."""
    env_path = root / ".env"
    if not env_path.is_file() or env_path.is_symlink():
        raise RuntimeError("Сначала создайте обычный .env через bash scripts/setup-server.sh.")
    original_env = env_path.read_text()
    # Значение нужно только для чтения config до создания сети; контейнеры не запускаются.
    environment = dict(os.environ, SERVER_NETWORK_GATEWAY="127.0.0.1")
    config = json.loads(docker(root, "compose", "config", "--format", "json", environment=environment).stdout)
    network_config = config["networks"]["default"]
    name = network_config["name"]
    if network_config.get("external") is not True or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,62}", name):
        raise RuntimeError("Ожидалась именованная external-сеть из compose.yml.")
    if name in {"bridge", "host", "none"}:
        raise RuntimeError("Нельзя использовать системную сеть Docker.")
    auth_host, auth_port = upstream(config, "authentication")
    api_host, api_port = upstream(config, "backend")
    if auth_host.lower() == api_host.lower() or auth_port == api_port:
        raise RuntimeError("Auth и API должны иметь разные домены и HTTP-порты.")

    inspection = docker(root, "network", "inspect", name, check=False)
    if inspection.returncode:
        # Без --subnet/--gateway: свободный диапазон выбирает Docker IPAM.
        docker(root, "network", "create", "--driver", "bridge",
               "--label", f"{PROJECT_LABEL}={config['name']}", name)
        inspection = docker(root, "network", "inspect", name)
    network = json.loads(inspection.stdout)[0]
    if (network["Driver"] != "bridge" or network.get("Internal") or
            (network.get("Labels") or {}).get(PROJECT_LABEL) != config["name"]):
        raise RuntimeError("Сеть занята другим проектом или имеет неподходящий режим. Измените SERVER_NETWORK_NAME.")
    addresses = [entry for entry in network["IPAM"]["Config"] if ":" not in entry.get("Subnet", "")]
    if len(addresses) != 1:
        raise RuntimeError("Ожидалась одна IPv4-подсеть Docker bridge.")
    subnet = ipaddress.IPv4Network(addresses[0]["Subnet"])
    gateway = ipaddress.IPv4Address(addresses[0]["Gateway"])
    if gateway not in subnet or gateway in {subnet.network_address, subnet.broadcast_address} or subnet.prefixlen == 0:
        raise RuntimeError("Некорректный gateway Docker bridge.")
    settings = {"SERVER_NETWORK_NAME": name, "SERVER_NETWORK_SUBNET": str(subnet), "SERVER_NETWORK_GATEWAY": str(gateway)}
    for key, value in settings.items():
        if key in os.environ and os.environ[key] != value:
            raise RuntimeError(f"Выполните unset {key}: экспортированная переменная перекрывает .env.")

    template = (root / "Config/Server/nginx.conf.example").read_text()
    template = template.replace("@SERVER_NETWORK_SUBNET@", str(subnet))
    # Один проход: значения пользователя не становятся очередными шаблонами.
    replacements = {"auth.example.com": auth_host, "api.example.com": api_host,
                    "127.0.0.1:5080": f"127.0.0.1:{auth_port}", "127.0.0.1:5081": f"127.0.0.1:{api_port}"}
    nginx = re.sub("|".join(re.escape(key) for key in replacements), lambda match: replacements[match[0]], template)
    nginx = "# Generated by setup-server-network.py; edit the installed copy and set your TLS paths.\n" + nginx
    # Меняем только три сетевых ключа; пароли, COMPOSE_FILE и остальные строки сохраняются.
    updated_env = original_env
    for key, value in settings.items():
        pattern = rf"(?m)^[ \t]*(?:export[ \t]+)?{key}[ \t]*=.*$"
        if re.search(pattern, updated_env):
            updated_env = re.sub(pattern, f"{key}={value}", updated_env)
        else:
            updated_env = updated_env.rstrip("\n") + f"\n{key}={value}\n"

    local = root / ".local"
    if local.is_symlink():
        raise RuntimeError(".local должна быть обычной директорией.")
    local.mkdir(mode=0o700, exist_ok=True)
    atomic_write(local / "nginx.generated.conf", nginx)
    if updated_env != original_env:
        atomic_write(env_path, updated_env)
    print(f"Docker: {name}, подсеть {subnet}, gateway {gateway}.")
    print("Настройки сети записаны в .env. Конфигурация Nginx: .local/nginx.generated.conf.")
    print("Установите её с вашими TLS-путями, выполните nginx -t и reload. Затем docker compose up -d.")


if __name__ == "__main__":
    try:
        prepare(Path(__file__).resolve().parent.parent)
    except (RuntimeError, OSError, ValueError, KeyError, IndexError, TypeError, subprocess.TimeoutExpired) as error:
        # Не печатаем ответы Compose/JSON: они могут содержать credentials из .env.
        message = str(error) if isinstance(error, RuntimeError) else "Не удалось подготовить сеть; проверьте Docker и локальную конфигурацию."
        print(message, file=sys.stderr)
        sys.exit(1)
