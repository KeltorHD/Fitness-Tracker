#!/usr/bin/env python3
"""Offline provenance, localization, media integrity and generated-resource validation."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
from PIL import Image

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
assert len(document['entries']) == manifest['selectedExerciseCount'] == manifest['upstreamExerciseCount'] == 876
assert english['locale'] == 'en' and len(english['entries']) == 876
assert english['source'] == document['source']
for ru, en in zip(document['entries'], english['entries']):
    original = source[en['sourceID']]
    assert ru['id'] == en['id'] and ru['images'] == en['images']
    assert en['name'] == original['name'] and en['steps'] == [s for s in original['instructions'] if s.strip()]
assert len(manifest['images']) == 1746
assert len([entry for entry in document['entries'] if entry['imagesUnavailable']]) == 3
assert len([entry for entry in document['entries'] if entry['techniqueUnavailable']]) == 5
generated = json.loads((root / 'Data/ExerciseLibrary/generated-media.json').read_text())
generated_provenance = json.loads((root / 'Data/ExerciseLibrary/generated-media.provenance.json').read_text())
generated_files = {item['path'] for entry in generated_provenance['entries'] for item in entry['files']}
expected = {image for entry in document['entries'] for image in entry['images']}
assert expected == {item['path'] for item in manifest['images']}
assert expected | {p for p in generated_files if p.endswith('.jpg')} == {str(p.relative_to(root / 'Resources/ExerciseMedia')) for p in (root / 'Resources/ExerciseMedia').rglob('*.jpg')}
assert {p for p in generated_files if p.endswith('.gif')} == {str(p.relative_to(root / 'Resources/ExerciseMedia')) for p in (root / 'Resources/ExerciseMedia').rglob('*.gif')}
for entry in generated_provenance['entries']:
    assert entry['generator'] == 'built-in image_gen' and entry['prompt']
    media = generated[entry['sourceID']]
    assert {media['poster'], media['gif'], *media['frames']} == {item['path'] for item in entry['files']}
    for item in entry['files']:
        path = root / 'Resources/ExerciseMedia' / item['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']
        assert path.stat().st_size == item['bytes']
    with Image.open(root / 'Resources/ExerciseMedia' / media['gif']) as gif:
        assert 2 <= gif.n_frames <= 24 and gif.info.get('loop') == 0
        assert max(gif.size) <= 512
preserved = json.loads((root / 'Data/ExerciseLibrary/preserved-identities.json').read_text())
by_id = {entry['sourceID']: entry for entry in document['entries']}
assert len(preserved) == 100
for previous in preserved:
    assert all(by_id[previous['sourceID']][key] == previous[key] for key in ['sourceID', 'id', 'name'])
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
    assert re.search('[А-Яа-яЁё]', entry['name'])
    assert bool(entry['steps']) == bool(source[entry['sourceID']]['instructions'])
    assert not entry['steps'] or len(entry['steps']) >= 3
    assert entry['generatedMedia'] == generated.get(entry['sourceID'])
    assert all(re.search('[А-Яа-яЁё]', step) for step in entry['steps'])
    if index < 8: assert entry['id'] == f'10000000-0000-0000-0000-{index + 1:012d}'
resource = root / 'Sources/FitnessTrackerCore/Resources/ExerciseLibrary.ru.json'
original = resource.read_bytes()
original_english = english_resource.read_bytes()
subprocess.run([sys.executable, str(root / 'scripts/import-exercise-library.py')], check=True, stdout=subprocess.DEVNULL)
assert resource.read_bytes() == original, 'Generated resource differs from checked-in Russian translations'
assert english_resource.read_bytes() == original_english, 'English resource differs from pinned source'
print(f'Exercise library: 876 Russian entries, 1746 original JPEGs, {len(generated)} generated animations, preserved IDs, SHA-256 and reproducible offline generation: OK.')
