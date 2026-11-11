#!/usr/bin/env python3
"""Guard product branding while preserving explicitly documented installed identities."""
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
            # The existing archive extension remains part of the public file contract.
            visible = value.replace('.fitnesstracker', '')
            assert not re.search('fitsession|fitnesstracker', visible, re.I), f'Old visible branding: {path}'
for path in (ROOT / 'docs/previews').glob('*.svg'):
    assert not re.search('fitsession|fitnesstracker', path.read_text(), re.I), f'Old mockup branding: {path}'

# Assemblies can be renamed; persisted sessions and encrypted data must retain their purposes.
for service in ['Authentication', 'Backend']:
    program = (ROOT / service / 'Program.cs').read_text()
    assert f'SetApplicationName("FitnessTracker.{service}")' in program
auth = (ROOT / 'Authentication/Program.cs').read_text()
assert 'options.Cookie.Name = "__Host-FitnessTrackerAuth"' in auth
assert 'options.Cookie.Name = "__Host-FitnessTrackerPasskey"' in auth
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

# Xcode variable aliases must keep existing Local.xcconfig values and accept the new names.
settings = dict(re.findall(r'^([A-Z_]+)\s*=\s*(.*?)\s*$',
                          (ROOT / 'Config/Base.xcconfig').read_text(), re.M))
def expand(value, variables):
    return re.sub(r'\$\(([^)]+)\)', lambda match: expand(variables[match[1]], variables), value)

old = settings | {'FITSESSION_BUNDLE_ID': 'org.owner.existing',
                  'FITSESSION_APP_GROUP': 'group.owner.existing',
                  'FITSESSION_CLOUD_CONTAINER': 'iCloud.owner.existing'}
new = settings | {'FITNESS_TRACKER_BUNDLE_ID': 'org.owner.new',
                  'FITNESS_TRACKER_APP_GROUP': 'group.owner.new',
                  'FITNESS_TRACKER_CLOUD_CONTAINER': 'iCloud.owner.new'}
for fixture, suffix in [(old, 'existing'), (new, 'new')]:
    assert expand(fixture['FITNESS_TRACKER_BUNDLE_ID'], fixture) == 'org.owner.' + suffix
    assert expand(fixture['FITNESS_TRACKER_APP_GROUP'], fixture) == 'group.owner.' + suffix
    assert expand(fixture['FITNESS_TRACKER_CLOUD_CONTAINER'], fixture) == 'iCloud.owner.' + suffix
print('FitLife branding, renamed targets/package, localized names and signing compatibility: OK.')
