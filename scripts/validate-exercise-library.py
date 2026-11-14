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
document = json.loads((root / 'Sources/FitLifeCore/Resources/ExerciseLibrary.ru.json').read_text())
english_resource = root / 'Sources/FitLifeCore/Resources/ExerciseLibrary.en.json'
english = json.loads(english_resource.read_text())
source = {item['id']: item for item in json.loads((vendor / 'exercises.selected.json').read_text())}
custom_items = json.loads((root / 'Data/ExerciseLibrary/custom-exercises.json').read_text())
custom = {item['id']: item for item in custom_items}
assert len(custom) == len(custom_items) and not set(source) & set(custom)
assert all(item['id'].startswith('FitLife_') and re.fullmatch(r'https://[^\s]+', item['referenceURL'])
           for item in custom_items)
source.update(custom)
reviewed = json.loads((root / 'Data/ExerciseLibrary/reviewed-exercises.json').read_text())
assert hashlib.sha256((vendor / 'exercises.selected.json').read_bytes()).hexdigest() == manifest['selectedDataSHA256']
assert hashlib.sha256((vendor / 'LICENSE.md').read_bytes()).hexdigest() == manifest['licenseSHA256']
assert document['source']['revision'] == manifest['revision']
assert document['source']['licenseText'] == (vendor / 'LICENSE.md').read_text()
assert manifest['selectedExerciseCount'] == manifest['upstreamExerciseCount'] == 876
assert len(document['entries']) == manifest['selectedExerciseCount'] + len(custom)
assert english['locale'] == 'en' and len(english['entries']) == len(document['entries'])
assert english['source'] == document['source']
for ru, en in zip(document['entries'], english['entries']):
    original = source[en['sourceID']]
    assert ru['id'] == en['id'] and ru['images'] == en['images']
    assert ru['trainingRegions'] == en['trainingRegions']
    assert (ru.get('variantGroup') or {}).get('id') == (en.get('variantGroup') or {}).get('id')
    authored = reviewed.get(en['sourceID'], {}).get('englishSteps')
    english_name = reviewed.get(en['sourceID'], {}).get('englishName', original['name'])
    assert en['name'] == english_name
    if english_name != original['name']:
        assert reviewed[en['sourceID']].get('englishNameCorrectionReason', '').strip()
        assert original['name'] in ru['aliases']
    assert en['steps'] == (authored if authored is not None else [s for s in original['instructions'] if s.strip()])
    if authored is not None:
        assert len(authored) >= 3
        assert re.fullmatch(r'https://[^\s]+', reviewed[en['sourceID']]['instructionSourceURL'])
        if original['instructions']:
            assert reviewed[en['sourceID']].get('instructionCorrectionReason', '').strip()
assert len(manifest['images']) == 1746
unavailable = {
    source_id for source_id, item in source.items()
    if (not item['images'] or reviewed.get(source_id, {}).get('excludeSourceImages', False))
    and not reviewed.get(source_id, {}).get('replacementImageSourceID')
}
assert {entry['sourceID'] for entry in document['entries'] if entry['imagesUnavailable']} == unavailable
assert not any(entry['techniqueUnavailable'] for entry in document['entries'])
generated = json.loads((root / 'Data/ExerciseLibrary/generated-media.json').read_text())
generated_provenance = json.loads((root / 'Data/ExerciseLibrary/generated-media.provenance.json').read_text())
generated_files = {item['path'] for entry in generated_provenance['entries'] for item in entry['files']}
expected = {image for item in source.values() for image in item['images']}
assert expected == {item['path'] for item in manifest['images']}
replacements = {
    f'{source_id}/replacement-{index}.jpg'
    for source_id, review in reviewed.items() if review.get('replacementImageSourceID')
    for index in range(2)
}
assert expected | replacements | {p for p in generated_files if p.endswith('.jpg')} == {str(p.relative_to(root / 'Resources/ExerciseMedia')) for p in (root / 'Resources/ExerciseMedia').rglob('*.jpg')}
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
    entry = by_id[previous['sourceID']]
    assert entry['id'] == previous['id']
    assert previous['name'] == entry['name'] or previous['name'] in entry['aliases']
for image in manifest['images']:
    path = image['path']
    assert '..' not in path and not path.startswith('/')
    data = (root / 'Resources/ExerciseMedia' / path).read_bytes()
    assert data[:2] == b'\xff\xd8' and data[-2:] == b'\xff\xd9', path
    assert len(data) == image['bytes'], path
    assert hashlib.sha256(data).hexdigest() == image['sha256'], path
for index, entry in enumerate(document['entries']):
    review = reviewed.get(entry['sourceID'], {})
    if review.get('excludeSourceImages', False):
        assert review.get('imageExclusionReason', '').strip()
        assert source[entry['sourceID']]['images']
        donor_id = review.get('replacementImageSourceID')
        if donor_id:
            assert donor_id in source and donor_id != entry['sourceID']
            assert review.get('replacementImageReason', '').strip()
            assert not reviewed.get(donor_id, {}).get('excludeSourceImages', False)
            assert entry['images'] == [f"{entry['sourceID']}/replacement-{index}.jpg" for index in range(2)]
            for replacement, donor in zip(entry['images'], source[donor_id]['images']):
                assert (root / 'Resources/ExerciseMedia' / replacement).read_bytes() == (root / 'Resources/ExerciseMedia' / donor).read_bytes()
        else:
            assert entry['images'] == []
    else:
        assert not review.get('replacementImageSourceID')
        assert entry['images'] == source[entry['sourceID']]['images']
    assert entry['englishName'] == review.get('englishName', source[entry['sourceID']]['name'])
    assert re.search('[А-Яа-яЁё]', entry['name'])
    assert bool(entry['steps']) == bool(source[entry['sourceID']]['instructions'] or reviewed.get(entry['sourceID'], {}).get('englishSteps'))
    assert entry['techniqueUnavailable'] == (not bool(entry['steps']))
    assert not entry['steps'] or len(entry['steps']) >= 3
    assert entry['generatedMedia'] == generated.get(entry['sourceID'])
    assert all(re.search('[А-Яа-яЁё]', step) for step in entry['steps'])
    if index < 8: assert entry['id'] == f'10000000-0000-0000-0000-{index + 1:012d}'
resource = root / 'Sources/FitLifeCore/Resources/ExerciseLibrary.ru.json'
original = resource.read_bytes()
original_english = english_resource.read_bytes()
subprocess.run([sys.executable, str(root / 'scripts/import-exercise-library.py')], check=True, stdout=subprocess.DEVNULL)
assert resource.read_bytes() == original, 'Generated resource differs from checked-in Russian translations'
assert english_resource.read_bytes() == original_english, 'English resource differs from pinned source'
print(f'Exercise library: {len(document["entries"])} Russian entries, 1746 original JPEGs, {len(generated)} generated animations, preserved IDs, SHA-256 and reproducible offline generation: OK.')
