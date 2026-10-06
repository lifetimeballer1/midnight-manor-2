import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('verify_assets', ROOT / 'scripts/verify_assets.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class AssetVerificationTests(unittest.TestCase):
    def setUp(self):
        self.path = ROOT / 'art/cottage_t1/cottage_t1.glb'
        self.manifest = json.loads((self.path.parent / 'manifest.json').read_text())

    def test_real_export_passes(self):
        self.assertTrue(verifier.validate(self.path, self.manifest)['passed'])

    def test_unrelated_export_is_rejected(self):
        forged = copy.deepcopy(self.manifest)
        forged['source_objects'][0] = 'MM Structural | forge | T05 Banner Pole'
        with self.assertRaisesRegex(AssertionError, 'Wrong exported object'):
            verifier.validate(self.path, forged)

    def test_modified_file_is_rejected(self):
        forged = copy.deepcopy(self.manifest)
        forged['sha256'] = '0' * 64
        with self.assertRaisesRegex(AssertionError, 'hash mismatch'):
            verifier.validate(self.path, forged)

    def test_missing_required_clip_is_rejected(self):
        forged = copy.deepcopy(self.manifest)
        forged['clips'] = ['walk']
        with self.assertRaisesRegex(AssertionError, 'Clip set mismatch'):
            verifier.validate(self.path, forged)


if __name__ == '__main__':
    unittest.main()
