"""Protect strict comparison from the false passes caused by output-only matching."""
import base64
import unittest
from evaluate import differences


def observed(out=b'', err=b'', code=0, state='EXITED'):
    return dict(state=state, exit_code=code, stdout_base64=base64.b64encode(out).decode(),
                stderr_base64=base64.b64encode(err).decode())


class StrictComparisonTests(unittest.TestCase):
    def test_identical_success(self):
        self.assertEqual([], differences(observed(b'yes'), observed(b'yes')))

    def test_trailing_space_is_observable(self):
        self.assertIn('stdout_base64', differences(observed(b'x '), observed(b'x')))

    def test_crlf_is_not_lf(self):
        self.assertIn('stdout_base64', differences(observed(b'x\r\n'), observed(b'x\n')))

    def test_binary_output_is_not_decoded_for_comparison(self):
        self.assertIn('stdout_base64', differences(observed(b'\xff'), observed(b'\xfe')))

    def test_stderr_and_stdout_are_not_interchangeable(self):
        self.assertEqual(['stdout_base64', 'stderr_base64'],
                         differences(observed(err=b'error'), observed(b'error')))

    def test_exit_status_is_observable(self):
        self.assertEqual(['exit_code'], differences(observed(code=255), observed(code=0)))

    def test_matching_partial_timeout_is_never_a_pass(self):
        self.assertIn('process_state', differences(observed(b'x', state='TIMEOUT'), observed(b'x', state='TIMEOUT')))


if __name__ == '__main__':
    unittest.main()
