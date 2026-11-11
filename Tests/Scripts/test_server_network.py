"""Проверки подготовки сети без Docker daemon, рабочих .env и сетевых запросов."""

from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("server_network", ROOT / "scripts/setup-server-network.py")
NETWORK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NETWORK)


class ServerNetworkTests(unittest.TestCase):
    """Проверяет выбор сети, сохранность секретов, повторный запуск и отказы."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "Config/Server").mkdir(parents=True)
        (self.root / "Config/Server/nginx.conf.example").write_text((ROOT / "Config/Server/nginx.conf.example").read_text())
        self.original_env = (
            "# Keep existing credentials and storage\nAUTH_DB_PASSWORD='literal-$-secret'\n"
            "COMPOSE_FILE=compose.yml:.local/compose.storage.yml\nSERVER_NETWORK_GATEWAY=172.30.0.1\n"
        )
        (self.root / ".env").write_text(self.original_env)
        self.config = {
            "name": "fitness-tracker", "networks": {"default": {"name": "fitlife-server", "external": True}},
            "services": {
                name: {"environment": {"AllowedHosts": host}, "ports": [{"host_ip": "127.0.0.1", "target": 8080, "published": port}]}
                for name, host, port in [("authentication", "auth.example.com", "6080"), ("backend", "api.example.com;backend", "6081")]
            },
        }
        self.network = {
            "Driver": "bridge", "Internal": False, "Labels": {NETWORK.PROJECT_LABEL: "fitness-tracker"},
            "IPAM": {"Config": [{"Subnet": "172.24.0.0/16", "Gateway": "172.24.0.1"}]},
        }
        self.exists = False
        self.commands = []
        self.fail_creation = False
        self.environment = patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def docker(self, root, *arguments, environment=None, check=True):
        self.commands.append(arguments)
        if arguments[0] == "compose":
            self.assertEqual(environment["SERVER_NETWORK_GATEWAY"], "127.0.0.1")
            return subprocess.CompletedProcess(arguments, 0, json.dumps(self.config))
        if arguments[:2] == ("network", "inspect"):
            return subprocess.CompletedProcess(arguments, 0 if self.exists else 1, json.dumps([self.network]))
        if arguments[:2] == ("network", "create"):
            if self.fail_creation:
                raise RuntimeError("No free address pools")
            self.exists = True
            return subprocess.CompletedProcess(arguments, 0, "network-id")
        self.fail(f"Unexpected command: {arguments}")

    def prepare(self):
        with patch.object(NETWORK, "docker", self.docker), redirect_stdout(io.StringIO()) as output:
            NETWORK.prepare(self.root)
            return output.getvalue()

    def test_auto_allocation_preserves_secrets_and_storage_and_is_repeatable(self):
        output = self.prepare()
        create = next(command for command in self.commands if command[:2] == ("network", "create"))
        self.assertNotIn("--subnet", create)
        self.assertNotIn("--gateway", create)
        content = (self.root / ".env").read_text()
        self.assertIn("AUTH_DB_PASSWORD='literal-$-secret'\n", content)
        self.assertIn("COMPOSE_FILE=compose.yml:.local/compose.storage.yml\n", content)
        self.assertIn("SERVER_NETWORK_GATEWAY=172.24.0.1\n", content)
        self.assertNotIn("secret", output)
        self.assertEqual((self.root / ".env").stat().st_mode & 0o777, 0o600)
        generated = (self.root / ".local/nginx.generated.conf").read_text()
        self.assertIn("allow 172.24.0.0/16;", generated)
        self.assertIn("deny all;", generated)
        self.assertIn("http://127.0.0.1:6080", generated)
        self.assertIn("http://127.0.0.1:6081", generated)
        self.assertNotIn("@SERVER_NETWORK_SUBNET@", generated)
        self.prepare()
        self.assertEqual(content, (self.root / ".env").read_text())
        self.assertEqual(sum(command[:2] == ("network", "create") for command in self.commands), 1)

    def test_existing_foreign_network_is_rejected_without_modifying_files(self):
        self.exists = True
        self.network["Labels"] = {}
        with self.assertRaisesRegex(RuntimeError, "другим проектом"):
            self.prepare()
        self.assertEqual((self.root / ".env").read_text(), self.original_env)
        self.assertFalse((self.root / ".local").exists())

    def test_pool_exhaustion_does_not_change_existing_configuration(self):
        self.fail_creation = True
        with self.assertRaisesRegex(RuntimeError, "address pools"):
            self.prepare()
        self.assertEqual((self.root / ".env").read_text(), self.original_env)
        self.assertFalse((self.root / ".local").exists())

    def test_exported_stale_gateway_is_rejected_without_writing_files(self):
        os.environ["SERVER_NETWORK_GATEWAY"] = "172.30.0.1"
        with self.assertRaisesRegex(RuntimeError, "unset SERVER_NETWORK_GATEWAY"):
            self.prepare()
        self.assertEqual((self.root / ".env").read_text(), self.original_env)

    def test_public_upstream_and_nginx_directive_injection_are_rejected(self):
        for value in ["auth.example.com\ninclude /tmp/injected", "auth.example.com\n}", "https://auth.example.com"]:
            with self.subTest(value=value):
                self.config["services"]["authentication"]["environment"]["AllowedHosts"] = value
                with self.assertRaisesRegex(RuntimeError, "DNS-имя"):
                    self.prepare()
        self.config["services"]["authentication"]["environment"]["AllowedHosts"] = "auth.example.com"
        self.config["services"]["backend"]["ports"][0]["host_ip"] = "0.0.0.0"
        with self.assertRaisesRegex(RuntimeError, "127.0.0.1"):
            self.prepare()
        self.assertFalse(any(command[0] == "network" for command in self.commands))


if __name__ == "__main__":
    unittest.main()
