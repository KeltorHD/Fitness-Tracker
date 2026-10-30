#!/usr/bin/env python3
"""Guard product branding while preserving explicitly documented installed identities."""
from pathlib import Path
import json
import plistlib
import re

import yaml

ROOT = Path(__file__).resolve().parent.parent
spec = yaml.safe_load((ROOT / 'project.yml').read_text())
assert spec['name'] == 'FitnessTracker'
assert all(name.startswith('FitnessTracker') for name in spec['schemes'])
assert (ROOT / 'Sources/FitnessTrackerCore').is_dir()
assert (ROOT / 'Tests/FitnessTrackerCoreTests').is_dir()
assert not (ROOT / 'Sources/FitSessionCore').exists()
assert not (ROOT / 'Tests/FitSessionCoreTests').exists()
for name in ['App', 'Watch', 'Widgets']:
    info = plistlib.loads((ROOT / f'Config/{name}-Info.plist').read_bytes())
    assert info['CFBundleDisplayName'].startswith('FitnessTracker')
for path in ['Resources/Localizable.xcstrings', 'Resources/InfoPlist.xcstrings']:
    catalog = json.loads((ROOT / path).read_text())
    for entry in catalog['strings'].values():
        for language in ['ru', 'en']:
            value = entry['localizations'][language]['stringUnit']['value']
            assert not re.search('fitsession', value, re.I), f'Old visible branding: {path}'
for path in (ROOT / 'docs/previews').glob('*.svg'):
    assert not re.search('fitsession', path.read_text(), re.I), f'Old mockup branding: {path}'

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
print('FitnessTracker branding, renamed targets/package, localized names and signing compatibility: OK.')
