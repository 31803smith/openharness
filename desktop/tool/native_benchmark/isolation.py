"""Identity checks shared by the disposable benchmark builder and runner."""
from pathlib import Path
import plistlib
import re


BENCHMARK_NAME = 'Harness Benchmark'
BENCHMARK_ID = 'ai.autonomous.harness.benchmark'
PREVIEW_ID = 'ai.autonomous.harness.v2'
RELEASE_ID = 'ai.autonomous.harness'
KNOWN_NAMES = ('Harness', 'Harness V2', BENCHMARK_NAME)


def benchmark_configuration(source):
    """Replace exactly one known product/identifier in the copied config."""
    replacements = (
        ('PRODUCT_NAME', ('Harness', 'Harness V2'), BENCHMARK_NAME),
        ('PRODUCT_BUNDLE_IDENTIFIER', (PREVIEW_ID, RELEASE_ID), BENCHMARK_ID),
    )
    for key, expected, replacement in replacements:
        pattern = re.compile(rf'^{key}[ \t]*=[ \t]*(.*)$', re.MULTILINE)
        matches = list(pattern.finditer(source))
        if len(matches) != 1 or matches[0].group(1).strip() not in expected:
            raise ValueError(f'Expected one known {key} assignment in the preview config')
        source = pattern.sub(f'{key} = {replacement}', source)
    return source


def bundle_info(app):
    with (app / 'Contents/Info.plist').open('rb') as source:
        return plistlib.load(source)


def validate_benchmark_bundle(app):
    info = bundle_info(app)
    if (app.name != f'{BENCHMARK_NAME}.app'
            or info.get('CFBundleIdentifier') != BENCHMARK_ID
            or info.get('CFBundleExecutable') != BENCHMARK_NAME):
        raise ValueError('Expected the isolated Harness Benchmark product and identity')


def conflicting_previews(executable_paths):
    """Identify builds by bundle and location; production now shares their ID."""
    conflicts = []
    for line in executable_paths.splitlines():
        executable = Path(line.strip())
        if executable.parent.name != 'MacOS' or executable.parent.parent.name != 'Contents':
            continue
        app = executable.parent.parent.parent
        if app.name not in {f'{name}.app' for name in KNOWN_NAMES}:
            continue
        try:
            identifier = bundle_info(app).get('CFBundleIdentifier')
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            raise ValueError(f'Cannot identify running {app.name}: {error}') from error
        if identifier in (PREVIEW_ID, BENCHMARK_ID):
            conflicts.append(str(app))
        elif identifier == RELEASE_ID:
            installed_directories = {
                Path('/Applications').resolve(),
                (Path.home() / 'Applications').resolve(),
            }
            # A renamed development build must not become exempt merely by
            # gaining the installed app's bundle identifier. Standard install
            # locations remain allowed, as before; report other copies.
            if app.parent.resolve() not in installed_directories:
                conflicts.append(str(app))
        else:
            raise ValueError(f'Unrecognized running Harness identity: {identifier}')
    return conflicts
