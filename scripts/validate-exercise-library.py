#!/usr/bin/env python3
"""Offline provenance, localization, media integrity and generated-resource validation."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
vendor = root / 'ThirdParty/free-exercise-db'
manifest = json.loads((vendor / 'manifest.json').read_text())
document = json.loads((root / 'Sources/FitnessTrackerCore/Resources/ExerciseLibrary.ru.json').read_text())
english_resource = root / 'Sources/FitnessTrackerCore/Resources/ExerciseLibrary.en.json'
english = json.loads(english_resource.read_text())
source = {item['id']: item for item in json.loads((vendor / 'exercises.selected.json').read_text())}
assert hashlib.sha256((vendor / 'exercises.selected.json').read_bytes()).hexdigest() == manifest['selectedDataSHA256']
assert hashlib.sha256((vendor / 'LICENSE.md').read_bytes()).hexdigest() == manifest['licenseSHA256']
assert document['source']['revision'] == manifest['revision']
assert document['source']['licenseText'] == (vendor / 'LICENSE.md').read_text()
assert len(document['entries']) == manifest['selectedExerciseCount'] == 100
assert english['locale'] == 'en' and len(english['entries']) == 100
assert english['source'] == document['source']
for ru, en in zip(document['entries'], english['entries']):
    original = source[en['sourceID']]
    assert ru['id'] == en['id'] and ru['images'] == en['images']
    assert en['name'] == original['name'] and en['steps'] == original['instructions']
assert len(manifest['images']) == 200
expected = {image for entry in document['entries'] for image in entry['images']}
assert expected == {item['path'] for item in manifest['images']}
assert expected == {str(p.relative_to(root / 'Resources/ExerciseMedia')) for p in (root / 'Resources/ExerciseMedia').rglob('*.jpg')}
for image in manifest['images']:
    path = image['path']
    assert '..' not in path and not path.startswith('/')
    data = (root / 'Resources/ExerciseMedia' / path).read_bytes()
    assert data[:2] == b'\xff\xd8' and data[-2:] == b'\xff\xd9', path
    assert len(data) == image['bytes'], path
    assert hashlib.sha256(data).hexdigest() == image['sha256'], path
for index, entry in enumerate(document['entries']):
    assert entry['images'] == source[entry['sourceID']]['images']
    assert entry['englishName'] == source[entry['sourceID']]['name']
    assert re.search('[А-Яа-яЁё]', entry['name']) and len(entry['steps']) >= 3
    assert all(re.search('[А-Яа-яЁё]', step) for step in entry['steps'])
    if index < 8: assert entry['id'] == f'10000000-0000-0000-0000-{index + 1:012d}'
resource = root / 'Sources/FitnessTrackerCore/Resources/ExerciseLibrary.ru.json'
original = resource.read_bytes()
original_english = english_resource.read_bytes()
subprocess.run([sys.executable, str(root / 'scripts/import-exercise-library.py')], check=True, stdout=subprocess.DEVNULL)
assert resource.read_bytes() == original, 'Generated resource differs from checked-in Russian translations'
assert english_resource.read_bytes() == original_english, 'English resource differs from pinned source'
print('Exercise library: 100 Russian entries, 200 original JPEGs, SHA-256 and reproducible offline generation: OK.')
