#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v openssl >/dev/null
command -v python3 >/dev/null
command -v docker >/dev/null
docker compose version >/dev/null
if [[ -e .env || -e .local/certificates/signing.pfx || -e .local/certificates/encryption.pfx || -e .local/backend-certificates/encryption.pfx ]]; then
  echo 'Existing server configuration found. Keep its keys and edit .env manually.' >&2
  exit 1
fi
umask 077
mkdir -p .local/certificates
chmod 700 .local
# The parent .local protects files on the host; the mounted child is readable by the container UID.
chmod 755 .local/certificates
python3 - <<'PY'
from pathlib import Path
import secrets
text = Path('.env.example').read_text()
for key in ['AUTH_DB_PASSWORD', 'BACKEND_DB_PASSWORD', 'BACKEND_SERVICE_KEY', 'BACKEND_INTROSPECTION_SECRET', 'CERTIFICATE_PASSWORD']:
    text = text.replace(f'{key}=\n', f'{key}={secrets.token_hex(32)}\n')
Path('.env').write_text(text)
PY
certificate_password="$(python3 -c 'from pathlib import Path; print(next(line.split("=",1)[1] for line in Path(".env").read_text().splitlines() if line.startswith("CERTIFICATE_PASSWORD=")))')"
export FITNESS_TRACKER_CERTIFICATE_PASSWORD="$certificate_password"
for purpose in signing encryption; do
  # These protect OpenIddict tokens/Data Protection; Nginx manages HTTPS separately.
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 730 \
    -subj "/CN=FitLife $purpose" \
    -keyout ".local/certificates/$purpose.key" -out ".local/certificates/$purpose.crt" 2>/dev/null
  openssl pkcs12 -export -inkey ".local/certificates/$purpose.key" \
    -in ".local/certificates/$purpose.crt" -out ".local/certificates/$purpose.pfx" \
    -passout env:FITNESS_TRACKER_CERTIFICATE_PASSWORD
  chmod 444 ".local/certificates/$purpose.pfx"
done
unset FITNESS_TRACKER_CERTIFICATE_PASSWORD certificate_password
python3 scripts/setup-backend-keys.py
echo 'Token keys generated. Edit .env, run python3 scripts/setup-server-network.py, then configure host Nginx with your TLS certificates; follow docs/SERVER.md.'
