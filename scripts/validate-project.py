#!/usr/bin/env python3
"""Validate repository invariants/resources, not an XcodeGen or Apple SDK compiler."""
from pathlib import Path
import json
import plistlib
import re
import struct
import sys

try:
    import yaml
except ImportError:
    sys.exit('Install development dependency: python3 -m pip install -r requirements-dev.txt (use a venv).')

root = Path(__file__).resolve().parent.parent
required = ['Package.swift', 'project.yml', 'README.md', 'MAC_BUILD_GUIDE.md',
            'docs/IMPLEMENTATION_STATUS.md', 'docs/API_REFERENCES.md',
            'scripts/setup-linux.sh', 'scripts/setup-macos.sh', 'scripts/check-linux.sh']
for path in required:
    assert (root / path).is_file(), f'Missing {path}'
spec = yaml.safe_load((root / 'project.yml').read_text())
assert spec['name'] == 'FitnessTracker'
assert spec['packages']['FitnessTrackerCore']['path'] == '.'
assert set(spec['targets']) == {'FitnessTracker', 'FitnessTrackerWatch', 'FitnessTrackerWidgets', 'FitnessTrackerTests', 'FitnessTrackerUITests'}
assert spec['options']['deploymentTarget'] == {'iOS': '26.0', 'watchOS': '26.0'}
assert {'path': 'Resources/ExerciseMedia', 'type': 'folder', 'buildPhase': 'resources'} in spec['targets']['FitnessTracker']['sources']
assert 'FITNESS_TRACKER_APP' in spec['targets']['FitnessTracker']['settings']['base']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
assert 'FITNESS_TRACKER_APP' not in spec['targets']['FitnessTrackerWidgets']['settings']['base'].get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '')
assert {'package': 'FitnessTrackerCore'} in spec['targets']['FitnessTrackerWidgets']['dependencies']
assert spec['configs']['PersonalDebug'] == 'debug'
assert spec['configs']['PersonalRelease'] == 'release'
assert spec['schemes']['FitnessTracker Personal']['run']['config'] == 'PersonalDebug'
assert spec['schemes']['FitnessTracker Personal']['archive']['config'] == 'PersonalRelease'
assert spec['settings']['base']['FITNESS_TRACKER_CLOUD_SYNC_AVAILABLE'] == 'YES'
for config in ['PersonalDebug', 'PersonalRelease']:
    assert spec['settings']['configs'][config]['FITNESS_TRACKER_CLOUD_SYNC_AVAILABLE'] == 'NO'
    assert spec['targets']['FitnessTracker']['settings']['configs'][config]['CODE_SIGN_ENTITLEMENTS'] == 'Config/PersonalTeam.entitlements'
for path in spec['configFiles'].values(): assert (root / path).is_file()
covered = set()
for name, target in spec['targets'].items():
    assert target['platform'] in {'iOS', 'watchOS'}
    sources = target['sources']
    if isinstance(sources, str): sources = [sources]
    for source in sources:
        path = root / (source if isinstance(source, str) else source['path'])
        assert path.exists(), f'{name}: missing source {path}'
        covered.update(path.rglob('*.swift') if path.is_dir() else [path])
        if path.suffix == '.xcprivacy': assert source.get('buildPhase') == 'resources'
    settings = target['settings']['base']
    for key in ['INFOPLIST_FILE', 'CODE_SIGN_ENTITLEMENTS']:
        if key in settings: assert (root / settings[key]).is_file()
    for dependency in target.get('dependencies', []):
        if 'target' in dependency: assert dependency['target'] in spec['targets']
    assert 'capabilities' not in target, 'Use documented entitlements instead of capability pseudokeys'
assert set((root / 'Apple').rglob('*.swift')).issubset(covered), 'Unassigned Apple source'
for file in (root / 'Sources').rglob('*.swift'):
    assert not re.search(r'^import (SwiftUI|SwiftData|HealthKit|CloudKit|UIKit|ActivityKit|WidgetKit|StoreKit)', file.read_text(), re.M), f'Apple dependency in core: {file}'
plists = {}
for file in root.rglob('*'):
    if any(part in {'.git', '.build', '.toolchains', '.venv'} for part in file.parts): continue
    if file.suffix in {'.plist', '.entitlements', '.xcprivacy'}:
        plists[file.name] = plistlib.loads(file.read_bytes())
    elif file.suffix in {'.json', '.storekit', '.xcstrings'}:
        data = json.loads(file.read_text())
        if file.name == 'Contents.json':
            for image in data.get('images', []):
                if 'filename' in image: assert (file.parent / image['filename']).is_file()
    elif file.suffix == '.png':
        png = file.read_bytes()
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        width, height, depth, color = struct.unpack('>IIBB', png[16:26])
        if file.parent.suffix == '.appiconset':
            assert (width, height, depth, color) == (1024, 1024, 8, 2), f'Icon must be opaque RGB 1024x1024: {file}'
        else:
            assert width > 0 and height > 0, f'Empty PNG: {file}'
app = plists['App-Info.plist']
assert app['NSSupportsLiveActivities'] is True
assert 'remote-notification' in app['UIBackgroundModes']
assert app['NSHealthUpdateUsageDescription']
assert app['NSBluetoothAlwaysUsageDescription']
assert 'bluetooth-central' in app['UIBackgroundModes']
assert app['FitnessTrackerCloudSyncAvailable'] == '$(FITNESS_TRACKER_CLOUD_SYNC_AVAILABLE)'
archive_type = next(item for item in app['UTExportedTypeDeclarations']
                    if item['UTTypeIdentifier'] == 'com.fitnesstracker.archive')
assert archive_type['UTTypeConformsTo'] == ['public.json']
assert archive_type['UTTypeTagSpecification']['public.filename-extension'] == ['fitnesstracker']
document_types = {identifier: item for item in app['CFBundleDocumentTypes']
                  for identifier in item['LSItemContentTypes']}
assert document_types['com.fitnesstracker.archive']['LSHandlerRank'] == 'Owner'
assert document_types['com.fitnesstracker.archive']['CFBundleTypeRole'] == 'Viewer'
assert document_types['com.fitsession.archive']['LSHandlerRank'] == 'Owner'
assert document_types['public.json']['LSHandlerRank'] == 'Alternate'
assert document_types['public.comma-separated-values-text']['LSHandlerRank'] == 'Alternate'
assert document_types['public.comma-separated-values-text']['CFBundleTypeRole'] == 'Viewer'
legacy_type = next(item for item in app['UTExportedTypeDeclarations']
                   if item['UTTypeIdentifier'] == 'com.fitsession.archive')
assert legacy_type['UTTypeTagSpecification']['public.filename-extension'] == ['fitsession']
assert set(app['CFBundleURLTypes'][0]['CFBundleURLSchemes']) == {'fitnesstracker', 'fitsession'}
assert app['LSSupportsOpeningDocumentsInPlace'] is True
assert not app.get('UIDesignRequiresCompatibility', False), 'Native Liquid Glass must stay enabled'
assert plists['Watch-Info.plist']['WKCompanionAppBundleIdentifier'] == '$(FITNESS_TRACKER_BUNDLE_ID)'
assert plists['Watch-Info.plist']['WKApplication'] is True
assert plists['Widgets-Info.plist']['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
entitlements = plists['App.entitlements']
assert entitlements['com.apple.developer.healthkit'] is True
assert entitlements['com.apple.developer.icloud-services'] == ['CloudKit']
assert entitlements['com.apple.security.application-groups'] == plists['Widgets.entitlements']['com.apple.security.application-groups']
assert 'aps-environment' in entitlements
personal = plists['PersonalTeam.entitlements']
assert personal['com.apple.developer.healthkit'] is True
assert personal['com.apple.security.application-groups'] == entitlements['com.apple.security.application-groups']
assert not any(key.startswith('com.apple.developer.icloud') or key == 'aps-environment' for key in personal)
ui = '\n'.join(p.read_text() for p in (root / 'Apple').rglob('*.swift'))
for api in ['GlassEffectContainer', '.glassEffect()', '.glassEffectID(', '.glassEffectTransition(', '.buttonStyle(.glass)', '.buttonStyle(.glassProminent)']:
    assert api in ui, f'Missing required Liquid Glass API: {api}'
print(f'Project structure, {len(covered)} assigned source/resource entries, plists, asset catalogs and Liquid Glass usage: OK.')
print('XcodeGen generation and Apple SDK compatibility still require macOS/Xcode.')
