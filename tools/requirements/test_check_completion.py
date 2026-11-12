import hashlib
from pathlib import Path
import tempfile
import unittest
from check_completion import inspect


class CompletionGateTests(unittest.TestCase):
    def test_empty_manifest_cannot_pass(self):
        self.assertEqual('NOT_COMPLETE', inspect({}, Path('.'), 1)['status'])

    def test_stage_two_requires_stage_one_acceptance(self):
        result = inspect({'owner_acceptance': {'stage2': True}}, Path('.'), 2)
        self.assertIn('Stage 1 must be completed and accepted before stage 2.', result['errors'])

    def test_verified_label_without_artifacts_cannot_pass(self):
        matrix = self.matrix()
        matrix['requirements'][0]['evidence_refs'] = []
        self.assertTrue(any('no verification evidence' in e for e in inspect(matrix, Path('.'), 1)['errors']))

    def test_changed_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'evidence.json'
            artifact.write_bytes(b'original')
            matrix = self.matrix()
            matrix['evidence_catalog'][0]['sha256'] = hashlib.sha256(artifact.read_bytes()).hexdigest()
            artifact.write_bytes(b'changed')
            self.assertTrue(any('hash mismatch' in e for e in inspect(matrix, root, 1)['errors']))

    def test_skipped_verification_is_rejected(self):
        matrix = self.matrix()
        matrix['evidence_catalog'][0]['verification']['skipped'] = 1
        self.assertTrue(any('verification contract' in e for e in inspect(matrix, Path('.'), 1)['errors']))

    def test_pending_control_cannot_be_hidden_by_leaf_passes(self):
        matrix = self.matrix()
        matrix['requirements'].append({'id': 'NATIVE-ABI', 'stage': 1, 'kind': 'control', 'state': 'NOT_IMPLEMENTED'})
        self.assertTrue(any('NATIVE-ABI: required control' in e for e in inspect(matrix, Path('.'), 1)['errors']))

    def test_unexpanded_aggregate_cannot_be_claimed_complete(self):
        matrix = self.matrix()
        matrix['requirements'].append({'id': 'ALL-EXTENSIONS', 'stage': 1, 'kind': 'aggregate', 'state': 'VERIFIED'})
        self.assertTrue(any('ALL-EXTENSIONS: aggregate has not been expanded' in e for e in inspect(matrix, Path('.'), 1)['errors']))

    @staticmethod
    def matrix():
        return {
            'exhaustive': True, 'inventory_gaps': [],
            'target': {'php_version': '8.5.12', 'stage1': dict.fromkeys(
                ['language', 'cli', 'web', 'standard_extensions', 'existing_native_extension_binaries'], True)},
            'requirements': [{'id': 'EXAMPLE', 'stage': 1, 'kind': 'leaf', 'state': 'VERIFIED',
                              'sources': [{'url': 'https://www.php.net/'}], 'tests': [{'id': 'example'}],
                              'evidence_refs': ['test-evidence']}],
            'evidence_catalog': [{'id': 'test-evidence', 'path': 'evidence.json', 'sha256': '0' * 64,
                                  'verification': {'php_version': '8.5.12', 'complete_for_requirement': True,
                                                   'actual_execution': True, 'passed': 1, 'failed': 0,
                                                   'unexecuted': 0, 'skipped': 0}}],
            'owner_acceptance': {'stage1': True},
        }


if __name__ == '__main__':
    unittest.main()
