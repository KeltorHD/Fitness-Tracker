#!/usr/bin/env python3
"""Import a pinned, curated public-domain exercise snapshot and its original JPEGs.

Network is opt-in (--download-only). Normal generation is entirely offline.
Russian text is maintained in Data/ExerciseLibrary/*.tsv, never machine-translated at runtime.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import re
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent.parent
REVISION = 'f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5'
BASE = f'https://raw.githubusercontent.com/yuhonas/free-exercise-db/{REVISION}/'
VENDOR = ROOT / 'ThirdParty/free-exercise-db'
MEDIA = ROOT / 'Resources/ExerciseMedia'
RESOURCE = ROOT / 'Sources/FitSessionCore/Resources/ExerciseLibrary.ru.json'
ENGLISH_RESOURCE = ROOT / 'Sources/FitSessionCore/Resources/ExerciseLibrary.en.json'
MUSCLES = {
    'abdominals': 'Мышцы живота', 'abductors': 'Отводящие мышцы бедра',
    'adductors': 'Приводящие мышцы бедра', 'biceps': 'Бицепс', 'calves': 'Икроножные мышцы',
    'chest': 'Грудные мышцы', 'forearms': 'Мышцы предплечья', 'glutes': 'Ягодичные мышцы',
    'hamstrings': 'Задняя поверхность бедра', 'lats': 'Широчайшие мышцы спины',
    'lower back': 'Разгибатели спины', 'middle back': 'Средняя часть спины',
    'quadriceps': 'Квадрицепс', 'shoulders': 'Дельтовидные мышцы',
    'traps': 'Трапециевидные мышцы', 'triceps': 'Трицепс'
}
GROUPS = {**dict.fromkeys(['abductors', 'adductors', 'calves', 'glutes', 'hamstrings', 'quadriceps'], 'legs'),
          **dict.fromkeys(['lats', 'lower back', 'middle back', 'traps'], 'back'),
          **dict.fromkeys(['biceps', 'forearms', 'triceps'], 'arms'),
          'abdominals': 'core', 'chest': 'chest', 'shoulders': 'shoulders'}

LEGACY_SOURCE_IDS = ['Barbell_Squat', 'Barbell_Bench_Press_-_Medium_Grip', 'Bent_Over_Barbell_Row',
                     'Standing_Military_Press', 'Romanian_Deadlift', 'Pullups', 'Dumbbell_Bicep_Curl', 'Crunches']
LEGACY_IDS = {source_id: f'10000000-0000-0000-0000-{index + 1:012d}' for index, source_id in enumerate(LEGACY_SOURCE_IDS)}

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def selection():
    lines = (ROOT / 'Data/ExerciseLibrary/selection.tsv').read_text().splitlines()
    rows = [line.split('\t') for line in lines if line.strip()]
    assert len({row[0] for row in rows}) == len(rows)
    return rows

def fetch(relative):
    with urllib.request.urlopen(BASE + relative, timeout=45) as response:
        return response.read()

def download():
    source = json.loads(fetch('dist/exercises.json'))
    by_id = {item['id']: item for item in source}
    selected = [by_id[row[0]] for row in selection()]
    VENDOR.mkdir(parents=True, exist_ok=True)
    write_json(VENDOR / 'exercises.selected.json', selected)
    (VENDOR / 'LICENSE.md').write_bytes(fetch('LICENSE.md'))
    paths = [path for item in selected for path in item['images']]
    assert len(paths) == len(set(paths))
    def image(path):
        assert re.fullmatch(r'[A-Za-z0-9_()\-]+/[01]\.jpg', path), path
        target = MEDIA / path
        if not target.exists():
            data = fetch('exercises/' + path)
            assert data.startswith(b'\xff\xd8') and len(data) > 512, path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        data = target.read_bytes()
        assert data.startswith(b'\xff\xd8') and data.endswith(b'\xff\xd9'), path
        return {'path': path, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    with ThreadPoolExecutor(max_workers=8) as pool:
        images = list(pool.map(image, paths))
    write_json(VENDOR / 'manifest.json', {
        'repository': 'https://github.com/yuhonas/free-exercise-db', 'revision': REVISION,
        'license': 'Unlicense', 'upstreamExerciseCount': len(source),
        'selectedExerciseCount': len(selected), 'images': images,
        'selectedDataSHA256': hashlib.sha256((VENDOR / 'exercises.selected.json').read_bytes()).hexdigest(),
        'licenseSHA256': hashlib.sha256((VENDOR / 'LICENSE.md').read_bytes()).hexdigest()
    })
    print(f'Downloaded {len(selected)} exercises and {len(images)} original JPEGs ({sum(i["bytes"] for i in images):,} bytes).')

def generate():
    source = {item['id']: item for item in json.loads((VENDOR / 'exercises.selected.json').read_text())}
    translations = {}
    for line in (ROOT / 'Data/ExerciseLibrary/instructions.ru.tsv').read_text().splitlines():
        fields = line.split('\t')
        assert fields[0] not in translations, fields[0]
        assert len(fields) >= 4, fields[0]
        translations[fields[0]] = fields[1:]
    assert set(source) == set(translations) == {row[0] for row in selection()}
    entries = []
    for index, (source_id, name, aliases) in enumerate(selection()):
        item = source[source_id]
        assert 0 < len(name) <= 80 and re.search('[А-Яа-яЁё]', name)
        steps = translations[source_id]
        assert all(len(s) >= 20 and re.search('[А-Яа-яЁё]', s) for s in steps)
        stable_id = LEGACY_IDS.get(source_id) or str(uuid.uuid5(uuid.NAMESPACE_URL, 'https://github.com/yuhonas/free-exercise-db/' + source_id))
        entries.append({'id': stable_id, 'sourceID': source_id, 'name': name,
                        'englishName': item['name'], 'aliases': aliases.split(';'),
                        'group': GROUPS[item['primaryMuscles'][0]], 'equipment': item['equipment'],
                        'level': item['level'], 'primaryMuscles': [MUSCLES[m] for m in item['primaryMuscles']],
                        'secondaryMuscles': [MUSCLES[m] for m in item['secondaryMuscles']],
                        'steps': steps, 'images': item['images']})
    write_json(RESOURCE, {'schemaVersion': 1, 'locale': 'ru',
                         'source': {'name': 'free-exercise-db',
                                    'repositoryURL': 'https://github.com/yuhonas/free-exercise-db',
                                    'revision': REVISION, 'licenseName': 'Unlicense',
                                    'licenseText': (VENDOR / 'LICENSE.md').read_text()}, 'entries': entries})
    english_entries = []
    for entry in entries:
        item = source[entry['sourceID']]
        english_entries.append({**entry, 'name': item['name'],
            'primaryMuscles': item['primaryMuscles'], 'secondaryMuscles': item['secondaryMuscles'],
            'steps': item['instructions']})
    russian = json.loads(RESOURCE.read_text())
    write_json(ENGLISH_RESOURCE, {**russian, 'locale': 'en', 'entries': english_entries})
    print(f'Generated {len(entries)} fully Russian exercise entries at {RESOURCE.relative_to(ROOT)}.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download-only', action='store_true')
    args = parser.parse_args()
    download() if args.download_only else generate()
