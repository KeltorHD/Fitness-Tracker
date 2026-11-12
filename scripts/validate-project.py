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
assert spec['name'] == 'FitLife'
assert spec['packages']['FitLifeCore']['path'] == '.'
assert set(spec['targets']) == {'FitLife', 'FitLifeWatch', 'FitLifeWidgets', 'FitLifeTests', 'FitLifeUITests'}
assert spec['options']['deploymentTarget'] == {'iOS': '26.0', 'watchOS': '26.0'}
assert '.watchOS("26.0")' in (root / 'Package.swift').read_text(), 'Core must support the Watch target'
assert {'path': 'Resources/ExerciseMedia', 'type': 'folder', 'buildPhase': 'resources'} in spec['targets']['FitLife']['sources']
assert 'FITLIFE_APP' in spec['targets']['FitLife']['settings']['base']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
assert 'FITLIFE_APP' not in spec['targets']['FitLifeWidgets']['settings']['base'].get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '')
assert {'package': 'FitLifeCore'} in spec['targets']['FitLifeWidgets']['dependencies']
assert spec['configs']['PersonalDebug'] == 'debug'
assert spec['configs']['PersonalRelease'] == 'release'
assert spec['schemes']['FitLife Personal']['run']['config'] == 'PersonalDebug'
assert spec['schemes']['FitLife Personal']['archive']['config'] == 'PersonalRelease'
assert spec['settings']['base']['FITLIFE_CLOUD_SYNC_AVAILABLE'] == 'YES'
assert spec['settings']['base']['FITLIFE_AUTH_CALLBACK_MODE'] == 'https'
for config in ['PersonalDebug', 'PersonalRelease']:
    assert spec['settings']['configs'][config]['FITLIFE_CLOUD_SYNC_AVAILABLE'] == 'NO'
    assert spec['settings']['configs'][config]['FITLIFE_AUTH_CALLBACK_MODE'] == 'customScheme'
    assert spec['targets']['FitLife']['settings']['configs'][config]['CODE_SIGN_ENTITLEMENTS'] == 'Config/PersonalTeam.entitlements'
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
watch = plists['Watch-Info.plist']
assert watch['NSHealthShareUsageDescription'] and watch['NSHealthUpdateUsageDescription']
assert {'alarm', 'workout-processing'} <= set(watch['WKBackgroundModes'])
assert plists['Watch.entitlements']['com.apple.developer.healthkit'] is True
assert app['NSBluetoothAlwaysUsageDescription']
assert 'bluetooth-central' in app['UIBackgroundModes']
assert app['FitLifeCloudSyncAvailable'] == '$(FITLIFE_CLOUD_SYNC_AVAILABLE)'
assert app['FitLifeAuthenticationCallbackMode'] == '$(FITLIFE_AUTH_CALLBACK_MODE)'
assert app['FitLifeAuthenticationCallbackScheme'] == '$(FITLIFE_AUTH_CALLBACK_SCHEME)'
assert any(item['CFBundleURLSchemes'] == ['$(FITLIFE_AUTH_CALLBACK_SCHEME)'] for item in app['CFBundleURLTypes'])
archive_type = next(item for item in app['UTExportedTypeDeclarations']
                    if item['UTTypeIdentifier'] == 'com.fitlife.archive')
assert archive_type['UTTypeConformsTo'] == ['public.json']
assert archive_type['UTTypeTagSpecification']['public.filename-extension'] == ['fitlife']
document_types = {identifier: item for item in app['CFBundleDocumentTypes']
                  for identifier in item['LSItemContentTypes']}
assert document_types['com.fitlife.archive']['LSHandlerRank'] == 'Owner'
assert document_types['com.fitlife.archive']['CFBundleTypeRole'] == 'Viewer'
assert document_types['public.json']['LSHandlerRank'] == 'Alternate'
assert document_types['public.comma-separated-values-text']['LSHandlerRank'] == 'Alternate'
assert document_types['public.comma-separated-values-text']['CFBundleTypeRole'] == 'Viewer'
assert len(app['UTExportedTypeDeclarations']) == 1
assert set(document_types) == {'com.fitlife.archive', 'public.json', 'public.comma-separated-values-text'}
assert set(app['CFBundleURLTypes'][0]['CFBundleURLSchemes']) == {'fitlife'}
assert app['LSSupportsOpeningDocumentsInPlace'] is True
assert not app.get('UIDesignRequiresCompatibility', False), 'Native Liquid Glass must stay enabled'
assert plists['Watch-Info.plist']['WKCompanionAppBundleIdentifier'] == '$(FITLIFE_BUNDLE_ID)'
assert plists['Watch-Info.plist']['WKApplication'] is True
assert plists['Widgets-Info.plist']['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
entitlements = plists['App.entitlements']
assert entitlements['com.apple.developer.healthkit'] is True
assert entitlements['com.apple.developer.icloud-services'] == ['CloudKit']
assert entitlements['com.apple.security.application-groups'] == plists['Widgets.entitlements']['com.apple.security.application-groups']
assert 'aps-environment' in entitlements
assert entitlements['com.apple.developer.associated-domains'] == ['webcredentials:$(FITLIFE_AUTH_DOMAIN)']
personal = plists['PersonalTeam.entitlements']
assert personal['com.apple.developer.healthkit'] is True
assert 'com.apple.developer.associated-domains' not in personal
assert personal['com.apple.security.application-groups'] == entitlements['com.apple.security.application-groups']
assert not any(key.startswith('com.apple.developer.icloud') or key == 'aps-environment' for key in personal)
ui = '\n'.join(p.read_text() for p in (root / 'Apple').rglob('*.swift'))
for api in ['GlassEffectContainer', '.glassEffect()', '.glassEffectID(', '.glassEffectTransition(', '.buttonStyle(.glass)', '.buttonStyle(.glassProminent)']:
    assert api in ui, f'Missing required Liquid Glass API: {api}'
print(f'Project structure, {len(covered)} assigned source/resource entries, plists, asset catalogs and Liquid Glass usage: OK.')
print('XcodeGen generation and Apple SDK compatibility still require macOS/Xcode.')
