#!/usr/bin/env python3
"""Build synthetic boundary cases; the real Swift Core independently verifies every verdict."""
from copy import deepcopy
import json
from pathlib import Path
import sys
from uuid import UUID

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'Tests/Server/Fixtures/training-contract.json'
OUTPUT = ROOT / 'Tests/Server/Fixtures/training-validation.json'


def cases():
    fixtures = json.loads(SOURCE.read_text())
    results = []

    def add(name, index, accepted, edits=(), transform=None):
        record = deepcopy(fixtures[index])
        for path, value in edits:
            target = record['value']
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
        if transform:
            transform(record['value'])
        value = record['value']
        original = fixtures[index]['value']
        results.append(dict(name=name, kind=record['kind'], id=original.get('id', original.get('workoutID')),
                            accepted=accepted, value=value))

    for index in range(len(fixtures)):
        add(f'original-{index}', index, True)

    for length, valid in [(0, False), (1, True), (80, True), (81, False)]:
        for index in [0, 4]:
            add(f'name-{index}-{length}', index, valid, [(['name'], 'я' * length)])
    add('name-whitespace', 0, False, [(['name'], ' \t\n')])
    add('name-combining-80', 0, True, [(['name'], 'e\u0301' * 80)])
    add('name-family-emoji-81', 0, False, [(['name'], '👨‍👩‍👧‍👦' * 81)])
    add('exercise-name-empty', 0, False, [(['exercises', 0, 'exercise', 'name'], '')])
    add('exercise-muscle-unknown', 0, False, [(['exercises', 0, 'exercise', 'muscle'], 'unknown')])

    for seconds, valid in [(-1, False), (0, True), (3600, True), (3601, False)]:
        for index in [0, 4]:
            add(f'rest-{index}-{seconds}', index, valid, [(['restSeconds'], seconds)])
    for weight, valid in [(0, False), (0.125, True), (1000, True), (1000.125, False)]:
        add(f'body-weight-{weight}', 5, valid, [(['weightKG'], weight)])
        add(f'workout-body-weight-{weight}', 0, valid, [(['bodyWeightKG'], weight)])
    add('no-workout-body-weight', 0, True, [(['bodyWeightKG'], None)])
    add('unlinked-weigh-in', 5, True, [(['workoutID'], None)])
    add('status-unknown', 0, False, [(['status'], 'unknown')])
    add('completed-without-end', 0, False, [(['endedAt'], None)])
    add('active-with-end', 2, False, [(['endedAt'], 1700001500)])
    add('paused-without-pause', 1, False, [(['pausedAt'], None)])
    add('active-with-pause', 2, False, [(['pausedAt'], 1700001000)])
    add('end-before-start', 0, False, [(['endedAt'], 1700000000)])
    add('pause-before-start', 1, False, [(['pausedAt'], 1700000000)])
    add('negative-paused-seconds', 0, False, [(['pausedSeconds'], -0.1)])
    add('incorrect-pause-total', 0, False, [(['pausedSeconds'], 15.5)])
    add('completed-without-performed-sets', 3, False, [(['exercises', 0, 'sets', 0, 'completedAt'], None)])
    add('cancelled-without-sets', 2, True, [(['status'], 'cancelled'), (['endedAt'], 1700001000), (['restEndsAt'], None)])
    start = fixtures[0]['value']['startedAt']
    add('reversed-pause', 0, False, [(['pauses', 0, 'endedAt'], start + 49), (['pausedSeconds'], 0)])
    add('overlapping-pauses', 0, False, [(['pauses'], [dict(startedAt=start + 50, endedAt=start + 65), dict(startedAt=start + 60, endedAt=start + 70)]), (['pausedSeconds'], 25)])
    add('touching-pauses', 0, True, [(['pauses'], [dict(startedAt=start + 50, endedAt=start + 65), dict(startedAt=start + 65, endedAt=start + 75)]), (['pausedSeconds'], 25)])
    add('pause-after-workout', 0, False, [(['pauses', 0, 'endedAt'], start + 201), (['pausedSeconds'], 151)])
    add('performed-before-start', 0, False, [(['exercises', 0, 'sets', 0, 'completedAt'], start - 1)])
    add('performed-after-end', 0, False, [(['exercises', 0, 'sets', 0, 'completedAt'], start + 201)])

    base = ['exercises', 0, 'sets', 0]
    for reps, valid in [(-1, False), (0, False), (1, True), (1000, True), (1001, False)]:
        add(f'performed-repetitions-{reps}', 0, valid, [(base + ['repetitions'], reps)])
    add('pending-zero-repetitions', 0, True, [(['exercises', 0, 'sets', 2, 'repetitions'], 0)])
    for weight, valid in [(-0.1, False), (0, True), (1500, True), (1500.125, False)]:
        add(f'set-weight-{weight}', 0, valid, [(base + ['weightKG'], weight)])
    for multiplier, valid in [(None, True), (0, False), (1, True), (10, True), (11, False)]:
        add(f'load-multiplier-{multiplier}', 0, valid, [(base + ['loadMultiplier'], multiplier)])
    for count, valid in [(0, True), (2000, True), (2001, False)]:
        add(f'set-note-{count}', 0, valid, [(base + ['note'], 'e\u0301' * count)])
    add('set-note-null', 0, True, [(base + ['note'], None)])
    add('no-sets', 0, False, [(['exercises', 0, 'sets'], [])])
    for count in [1, 30, 31]:
        sets = [dict(deepcopy(fixtures[0]['value']['exercises'][0]['sets'][0]), id=str(UUID(int=20000 + n))) for n in range(count)]
        add(f'workout-set-count-{count}', 0, count <= 30, [(['exercises', 0, 'sets'], sets)])
    add('duplicate-row-id', 0, False, [(['exercises', 1, 'id'], fixtures[0]['value']['exercises'][0]['id'])])
    add('duplicate-set-id', 0, False, [(['exercises', 1, 'sets', 0, 'id'], fixtures[0]['value']['exercises'][0]['sets'][0]['id'])])

    drop = ['exercises', 0, 'sets', 1]
    add('drop-list-null', 0, True, [(drop + ['dropStages'], None)])
    add('drop-list-empty', 0, False, [(drop + ['dropStages'], [])])
    add('warmup-with-drops', 0, False, [(drop + ['isWarmup'], True)])
    add('drop-same-weight', 0, False, [(drop + ['dropStages', 0, 'weightKG'], 60.25)])
    add('drop-growing-weight', 0, False, [(drop + ['dropStages', 1, 'weightKG'], 41)])
    add('drop-duplicate-id', 0, False, [(drop + ['dropStages', 1, 'id'], fixtures[0]['value']['exercises'][0]['sets'][1]['id'])])
    add('drop-completion-before-base', 0, False, [(drop + ['dropStages', 0, 'completedAt'], start + 19)])
    add('drop-completion-skips-base', 0, False, [(drop + ['completedAt'], None)])
    add('drop-completion-skips-stage', 0, False, [(drop + ['dropStages', 0, 'completedAt'], None)])
    for count in [5, 6]:
        stages = [dict(id=str(UUID(int=10000 + n)), repetitions=1, weightKG=50 - n,
                       completedAt=start + 25 + n) for n in range(count)]
        add(f'drop-count-{count}', 0, count == 5, [(drop + ['dropStages'], stages)])
    add('singleton-superset', 0, False, [(['exercises', 1, 'supersetID'], None)])
    third = deepcopy(fixtures[0]['value']['exercises'][1])
    third['id'] = str(UUID(int=30000))
    third['sets'][0]['id'] = str(UUID(int=30001))
    interrupted = deepcopy(fixtures[0]['value']['exercises']) + [third]
    interrupted[1]['supersetID'] = None
    add('interrupted-superset', 0, False, [(['exercises'], interrupted)])

    for count, valid in [(0, False), (1, True), (30, True), (31, False)]:
        add(f'planned-set-count-{count}', 4, valid, [(['exercises', 1, 'setCount'], count)])
    add('plan-no-base-exercises', 4, False, [(['exercises'], [])])
    add('plan-no-variation-exercises', 4, False, [(['variations', 0, 'exercises'], [])])
    add('plan-empty-variation-name', 4, False, [(['variations', 0, 'name'], '')])
    add('plan-null-base-name', 4, True, [(['baseVariationName'], None)])
    add('plan-empty-base-name', 4, False, [(['baseVariationName'], '')])
    add('plan-duplicate-variation-id', 4, False, [(['variations', 0, 'id'], fixtures[4]['value']['id'])])
    add('plan-duplicate-row-across-variations', 4, False, [(['variations', 0, 'exercises', 0, 'id'], fixtures[4]['value']['exercises'][0]['id'])])
    add('plan-target-count-mismatch', 4, False, [(['exercises', 0, 'setCount'], 3)])
    add('plan-performed-target', 4, False, [(['exercises', 0, 'plannedSets', 0, 'completedAt'], start)])
    add('plan-zero-target-repetitions', 4, False, [(['exercises', 0, 'plannedSets', 0, 'repetitions'], 0)])
    add('plan-unknown-muscle', 4, False, [(['muscles'], ['unknown'])])
    add('plan-unknown-region', 4, False, [(['muscleRegions'], ['unknown'])])
    add('plan-weekday-zero', 4, False, [(['preferredWeekdays'], [0])])
    add('plan-weekday-eight', 4, False, [(['preferredWeekdays'], [8])])
    add('plan-weekday-boundaries', 4, True, [(['preferredWeekdays'], [1, 7])])

    for bpm, valid in [(0, False), (0.5, False), (1, True), (300, True), (300.01, False)]:
        add(f'pulse-bpm-{bpm}', 7, valid, [(['readings', 0, 'beatsPerMinute'], bpm)])
    add('pulse-empty', 7, True, [(['readings'], [])])
    add('pulse-unknown-version', 7, False, [(['schemaVersion'], 2)])
    add('pulse-unknown-mode', 7, False, [(['mode'], 'unknown')])
    add('pulse-mi-fitness', 7, True, [(['origin'], 'miFitnessCloud')])
    add('pulse-mi-fitness-wrong-mode', 7, False, [(['origin'], 'miFitnessCloud'), (['mode'], 'bluetooth')])
    add('pulse-unknown-origin', 7, False, [(['origin'], 'unknown')])
    add('pulse-wrong-origin-mode', 7, False, [(['mode'], 'bluetooth')])
    add('pulse-same-timestamps', 7, False, [(['readings', 1, 'date'], fixtures[7]['value']['readings'][0]['date'])])
    add('pulse-reversed-timestamps', 7, False, [(['readings', 1, 'date'], start)])
    for count in [10000, 10001]:
        add(f'pulse-count-{count}', 7, count == 10000,
            [(['readings'], [dict(date=start + n * 5, beatsPerMinute=75.125) for n in range(count)])])
    for field in ['id', 'name', 'startedAt', 'status', 'exercises', 'pauses', 'notes', 'pausedSeconds']:
        add(f'required-workout-{field}-null', 0, False, [([field], None)])
    for field in ['exercises', 'variations', 'muscles', 'muscleRegions', 'muscleGroups', 'preferredWeekdays']:
        add(f'required-template-{field}-null', 4, False, [([field], None)])
    add('null-exercise-definition', 0, False, [(['exercises', 0, 'exercise'], None)])
    add('null-set-element', 0, False, [(['exercises', 1, 'sets'], [None])])
    add('null-drop-element', 0, False, [(drop + ['dropStages'], [None])])
    add('null-reading-element', 7, False, [(['readings'], [None])])
    add('numeric-string-weight', 5, False, [(['weightKG'], '75.25')])
    add('boolean-weight', 5, False, [(['weightKG'], True)])
    add('invalid-uuid', 0, False, [(['id'], 'not-a-uuid')])
    assert len({case['name'] for case in results}) == len(results)
    return results


if __name__ == '__main__':
    encoded = json.dumps(cases(), ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n'
    if sys.argv[1:] == ['--write']:
        OUTPUT.write_text(encoded)
    elif sys.argv[1:] == ['--verify']:
        assert OUTPUT.read_text() == encoded, 'Regenerate training-validation.json'
    else:
        raise SystemExit('Use --write or --verify')
    print(f'Training validation corpus: {len(cases())} deterministic boundary cases.')
