from pathlib import Path
import plistlib
import tempfile
import unittest

from isolation import (
    BENCHMARK_ID, BENCHMARK_NAME, PREVIEW_ID, RELEASE_ID,
    benchmark_configuration, conflicting_previews, validate_benchmark_bundle,
)


class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='harness-benchmark-check-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def app(self, folder, name, identifier, executable=None):
        bundle = self.root / folder / f'{name}.app'
        (bundle / 'Contents/MacOS').mkdir(parents=True)
        binary = executable or name
        with (bundle / 'Contents/Info.plist').open('wb') as output:
            plistlib.dump({'CFBundleIdentifier': identifier, 'CFBundleExecutable': binary}, output)
        return bundle, bundle / 'Contents/MacOS' / binary

    def test_current_and_legacy_product_names_are_replaced(self):
        for name in ('Harness', 'Harness V2'):
            with self.subTest(name=name):
                source = f'// product\nPRODUCT_NAME = {name}\nPRODUCT_BUNDLE_IDENTIFIER = {PREVIEW_ID}\n'
                result = benchmark_configuration(source)
                self.assertIn(f'PRODUCT_NAME = {BENCHMARK_NAME}\n', result)
                self.assertIn(f'PRODUCT_BUNDLE_IDENTIFIER = {BENCHMARK_ID}\n', result)
                self.assertTrue(result.startswith('// product\n'))

    def test_unknown_or_duplicate_configuration_fails_closed(self):
        known = f'PRODUCT_NAME = Harness\nPRODUCT_BUNDLE_IDENTIFIER = {PREVIEW_ID}\n'
        for source in (known.replace('Harness', 'Other'),
                       known.replace(PREVIEW_ID, RELEASE_ID),
                       known + 'PRODUCT_NAME = Harness\n',
                       known.replace('PRODUCT_NAME = Harness\n', '')):
            with self.subTest(source=source), self.assertRaises(ValueError):
                benchmark_configuration(source)

    def test_current_and_legacy_preview_processes_are_blocked(self):
        for name in ('Harness', 'Harness V2', BENCHMARK_NAME):
            with self.subTest(name=name):
                identifier = BENCHMARK_ID if name == BENCHMARK_NAME else PREVIEW_ID
                bundle, binary = self.app(name, name, identifier)
                self.assertEqual(conflicting_previews(str(binary)), [str(bundle)])

    def test_installed_app_and_non_app_commands_are_not_preview_processes(self):
        _, binary = self.app('installed', 'Harness', RELEASE_ID)
        self.assertEqual(conflicting_previews(f'{binary}\n/usr/bin/python3\n/bin/zsh'), [])

    def test_unknown_or_unreadable_running_harness_fails_closed(self):
        bundle, binary = self.app('unknown', 'Harness', 'unexpected')
        with self.assertRaises(ValueError):
            conflicting_previews(str(binary))
        (bundle / 'Contents/Info.plist').unlink()
        with self.assertRaises(ValueError):
            conflicting_previews(str(binary))

    def test_built_bundle_requires_both_isolated_identity_and_executable(self):
        bundle, _ = self.app('valid', BENCHMARK_NAME, BENCHMARK_ID)
        validate_benchmark_bundle(bundle)
        for folder, name, identifier, executable in (
            ('wrong-name', 'Harness', BENCHMARK_ID, BENCHMARK_NAME),
            ('wrong-id', BENCHMARK_NAME, PREVIEW_ID, BENCHMARK_NAME),
            ('wrong-binary', BENCHMARK_NAME, BENCHMARK_ID, 'Harness'),
        ):
            wrong, _ = self.app(folder, name, identifier, executable)
            with self.subTest(folder=folder), self.assertRaises(ValueError):
                validate_benchmark_bundle(wrong)


if __name__ == '__main__':
    unittest.main()
