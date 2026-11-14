import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('exercise_importer', ROOT / 'scripts/import-exercise-library.py')
importer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(importer)


class ExerciseLibraryDownloadTests(unittest.TestCase):
    def test_download_keeps_custom_exercises_out_of_pinned_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = root / 'Data/ExerciseLibrary'
            data.mkdir(parents=True)
            custom = [{
                'id': 'FitLife_Custom', 'referenceURL': 'https://example.com/exercise',
                'images': [], 'instructions': ['First step', 'Second step', 'Third step'],
            }]
            (data / 'custom-exercises.json').write_text(json.dumps(custom))
            (data / 'selection.tsv').write_text('Original\tНазвание\talias\nFitLife_Custom\tНовое\talias\n')
            original = [{'id': 'Original', 'images': ['Original/0.jpg', 'Original/1.jpg']}]
            jpeg = b'\xff\xd8' + b'x' * 600 + b'\xff\xd9'

            def fetch(path):
                if path == 'dist/exercises.json':
                    return json.dumps(original).encode()
                if path == 'LICENSE.md':
                    return b'fixture license'
                self.assertIn(path, ['exercises/Original/0.jpg', 'exercises/Original/1.jpg'])
                return jpeg

            with patch.object(importer, 'ROOT', root), \
                 patch.object(importer, 'VENDOR', root / 'vendor'), \
                 patch.object(importer, 'MEDIA', root / 'media'), \
                 patch.object(importer, 'fetch', side_effect=fetch), \
                 contextlib.redirect_stdout(io.StringIO()):
                importer.download()

            snapshot = json.loads((root / 'vendor/exercises.selected.json').read_text())
            manifest = json.loads((root / 'vendor/manifest.json').read_text())
            self.assertEqual(snapshot, original)
            self.assertEqual(manifest['selectedExerciseCount'], 1)
            self.assertEqual(len(manifest['images']), 2)
            self.assertEqual(json.loads((data / 'custom-exercises.json').read_text()), custom)


if __name__ == '__main__':
    unittest.main()
