#!/usr/bin/env python3
"""Check reviewed translations, placeholders, source coverage and resource membership offline.

This validates catalog inputs, not Xcode's catalog compilation or system localization behavior.
"""
from pathlib import Path
import importlib.util
import json
import plistlib
import re
import subprocess
import sys

import yaml

ROOT = Path(__file__).resolve().parent.parent


def load_json(path):
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            assert key not in result, f'{path}: duplicate key {key}'
            result[key] = value
        return result
    return json.loads((ROOT / path).read_text(), object_pairs_hook=unique_pairs)


english = load_json('Data/Localization/Interface.en.json')
russian = load_json('Data/Localization/Interface.ru.json')
assert russian.keys() <= english.keys(), 'Russian overrides must have English counterparts'
assert all(isinstance(value, str) and value.strip() for value in english.values())
paths = ['Resources/Localizable.xcstrings', 'Resources/InfoPlist.xcstrings']
catalogs = [load_json(path) for path in paths]
for path, catalog in zip(paths, catalogs):
    assert catalog['sourceLanguage'] == 'ru' and catalog['version'] == '1.0'
    for key, entry in catalog['strings'].items():
        assert entry['extractionState'] == 'manual', f'{path}: {key}'
        assert set(entry['localizations']) == {'ru', 'en'}, f'{path}: missing language for {key}'
        values = []
        for locale in ['ru', 'en']:
            unit = entry['localizations'][locale]['stringUnit']
            assert unit['state'] == 'translated' and unit['value'].strip(), f'{path}: {key}'
            # Runtime format calls use %@ with String arguments, never unchecked numeric types.
            assert re.sub(r'%%|%@', '', unit['value']).count('%') == 0, f'Unsafe format: {key}'
            values.append(unit['value'].count('%@'))
        assert values[0] == values[1], f'Placeholder mismatch: {key}'

ui = catalogs[0]['strings']
assert set(ui) == set(english)
for key, value in english.items():
    assert ui[key]['localizations']['en']['stringUnit']['value'] == value
    assert ui[key]['localizations']['ru']['stringUnit']['value'] == russian.get(key, key)
    if key != 'Русский':  # Language names remain recognizable autonyms in the picker.
        assert not re.search('[А-Яа-яЁё]', value), f'Untranslated English value: {key}'
for kind in ['workout', 'set', 'rep', 'completed.set', 'record']:
    for form in ['one', 'few', 'many', 'other']:
        assert f'{kind}.count.{form}' in ui, f'Missing count form: {kind}/{form}'

spec = importlib.util.spec_from_file_location('localization_tools', ROOT / 'scripts/localization-tools.py')
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)
sources = list((ROOT / 'Apple').rglob('*.swift')) + list((ROOT / 'Sources/FitnessTrackerCore').glob('*.swift'))
for path in sources:
    if {'Tests', 'UITests'} & set(path.parts):
        continue
    source = path.read_text()
    for start, end, parts, expressions in scanner.strings(source):
        key = '%@'.join(parts)
        if re.search('[А-Яа-яЁё]', key):
            assert key in ui, f'{path.relative_to(ROOT)}:{source[:start].count(chr(10))+1}: missing {key}'

project = yaml.safe_load((ROOT / 'project.yml').read_text())
for target in ['FitnessTracker', 'FitnessTrackerWidgets', 'FitnessTrackerWatch']:
    resources = project['targets'][target]['sources']
    assert {'path': paths[0], 'buildPhase': 'resources'} in resources, f'{target}: missing UI catalog'
    if target == 'FitnessTracker':
        assert {'path': paths[1], 'buildPhase': 'resources'} in resources
    info_path = project['targets'][target]['settings']['base']['INFOPLIST_FILE']
    info = plistlib.loads((ROOT / info_path).read_bytes())
    assert info['CFBundleLocalizations'] == ['ru', 'en'], f'{target}: declared languages'

before = [(ROOT / path).read_bytes() for path in paths]
subprocess.run([sys.executable, 'scripts/generate-localizations.py'], cwd=ROOT, check=True, capture_output=True)
assert before == [(ROOT / path).read_bytes() for path in paths], 'Catalog generation is not reproducible'
print(f'Localization: {len(ui)} RU/EN keys, placeholders, source coverage, count forms, targets and regeneration: OK.')
print('String Catalog compilation and UI/system behavior require Xcode validation.')
