#!/usr/bin/env python3
"""Validate FitLife branding and current configuration contracts."""
from pathlib import Path
import json
import plistlib
import re

import yaml

ROOT = Path(__file__).resolve().parent.parent
spec = yaml.safe_load((ROOT / 'project.yml').read_text())
assert spec['name'] == 'FitLife'
assert all(name.startswith('FitLife') for name in spec['schemes'])
assert (ROOT / 'Sources/FitLifeCore').is_dir()
assert (ROOT / 'Tests/FitLifeCoreTests').is_dir()
assert not (ROOT / 'Sources/FitnessTrackerCore').exists()
assert not (ROOT / 'Tests/FitnessTrackerCoreTests').exists()
assert not (ROOT / 'Sources/FitSessionCore').exists()
assert not (ROOT / 'Tests/FitSessionCoreTests').exists()
for name in ['App', 'Watch', 'Widgets']:
    info = plistlib.loads((ROOT / f'Config/{name}-Info.plist').read_bytes())
    assert info['CFBundleDisplayName'].startswith('FitLife')
for path in ['Resources/Localizable.xcstrings', 'Resources/InfoPlist.xcstrings']:
    catalog = json.loads((ROOT / path).read_text())
    for entry in catalog['strings'].values():
        for language in ['ru', 'en']:
            value = entry['localizations'][language]['stringUnit']['value']
            assert not re.search('fitsession|fitnesstracker', value, re.I), f'Old visible branding: {path}'
for path in (ROOT / 'docs/previews').glob('*.svg'):
    assert not re.search('fitsession|fitnesstracker', path.read_text(), re.I), f'Old mockup branding: {path}'

# Server cookies and encryption purposes use only the current product identity.
for service in ['Authentication', 'Backend']:
    program = (ROOT / service / 'Program.cs').read_text()
    assert f'SetApplicationName("FitLife.{service}")' in program
auth = (ROOT / 'Authentication/Program.cs').read_text()
assert 'options.Cookie.Name = "__Host-FitLifeAuth"' in auth
assert 'options.Cookie.Name = "__Host-FitLifePasskey"' in auth
solution = (ROOT / 'FitLife.Server.sln').read_text(encoding='utf-8-sig')
for reference in re.findall(r'"([^"\n]+\.csproj)"', solution):
    assert (ROOT / reference.replace('\\', '/')).is_file(), f'Missing project: {reference}'
for service in ['Authentication', 'Backend']:
    dockerfile = (ROOT / service / 'Dockerfile').read_text()
    assert f'{service}/FitLife.{service}.csproj' in dockerfile
    assert f'"FitLife.{service}.dll"' in dockerfile
for path in (ROOT / 'Authentication/Views').rglob('*.cshtml'):
    assert not re.search('fitsession|fitnesstracker', path.read_text(), re.I), f'Old auth branding: {path}'
email = (ROOT / 'Authentication/EmailTemplates/Confirmation.html').read_text()
assert not re.search('fitsession|fitnesstracker', email, re.I), 'Old email branding'
for path in ['Authentication/wwwroot/auth-ui.js',
             'ThirdParty/free-exercise-db/NOTICE.ru.md',
             'Config/Server/nginx.conf.example']:
    assert not re.search(r'fitness[\s_-]*tracker', (ROOT / path).read_text(), re.I), f'Old branding: {path}'

# FitLife build settings derive signing identities directly, without aliases.
settings = dict(re.findall(r'^([A-Z_]+)\s*=\s*(.*?)\s*$',
                          (ROOT / 'Config/Base.xcconfig').read_text(), re.M))
assert not any(key.startswith(('FITSESSION_', 'FITNESS_TRACKER_')) for key in settings)
assert settings['FITLIFE_BUNDLE_ID'] == 'com.example.fitlife'
def expand(value, variables):
    return re.sub(r'\$\(([^)]+)\)', lambda match: expand(variables[match[1]], variables), value)

fixture = settings | {'FITLIFE_BUNDLE_ID': 'org.owner.app'}
assert expand(fixture['FITLIFE_APP_GROUP'], fixture) == 'group.org.owner.app'
assert expand(fixture['FITLIFE_CLOUD_CONTAINER'], fixture) == 'iCloud.org.owner.app'

# Compose, example configuration and executable defaults must name the same neutral databases.
compose = yaml.safe_load((ROOT / 'compose.yml').read_text())
environment = dict(re.findall(r'^([A-Z_]+)=(.*)$', (ROOT / '.env.example').read_text(), re.M))
for prefix, service, database in [('AUTH', 'authentication', 'authentication'), ('BACKEND', 'backend', 'backend')]:
    database_service = 'auth-db' if prefix == 'AUTH' else 'backend-db'
    config = compose['services'][database_service]['environment']
    connection = compose['services'][service]['environment']['ConnectionStrings__Database']
    for suffix, postgres_key, connection_key in [('NAME', 'POSTGRES_DB', 'Database'), ('USER', 'POSTGRES_USER', 'Username')]:
        variable = f'{prefix}_DB_{suffix}'
        expected = '${' + variable + ':-' + database + '}'
        assert environment[variable] == database
        assert config[postgres_key] == expected
        assert f'{connection_key}={expected};' in connection
    for filename in ['Program.cs', 'DesignTimeDbContextFactory.cs']:
        assert f'Database={database};Username={database}' in (ROOT / service.capitalize() / filename).read_text()
print('FitLife branding, current signing identities and neutral database names: OK.')
