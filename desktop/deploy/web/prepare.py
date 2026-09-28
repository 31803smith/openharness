#!/usr/bin/env python3
"""Turn a published web bundle into the image's build context.

    python3 prepare.py <harness-web-release.json> <harness-web-X.Y.Z.tar.gz> <out-dir>

Writes <out-dir>/site/harness-web/ and <out-dir>/nginx.conf. Ported from the website's
fetch-harness-web.mjs + harness-web-assets.mjs, which prepared the same tree inside its image:

- the archive must match the manifest's SHA-256, and its own release.json the manifest;
- every file is also served from /harness-web/releases/<version>-<sha12>/, and index.html loads
  JavaScript, fonts and CanvasKit only from there, so an edge or browser cache holding an older
  release can never mix its assets into a newer page. The unversioned files stay for tabs opened
  before a deployment;
- the generated service worker is not started: it could keep serving an older app on its own.
"""
import hashlib
import json
import re
import shutil
import sys
import tarfile
from pathlib import Path, PurePosixPath

BASE_HREF = '/harness-web/'
LOADER = re.compile(r'_flutter\.loader\.load\(\{[\s\S]*?\}\);\s*(?=</script>)')


def fail(message: str) -> None:
    sys.exit(f'ERROR {message}')


def release_asset_base(release: dict) -> str:
    return f"{BASE_HREF}releases/{release['version']}-{release['sha256'][:12]}/"


def configure_release_assets(html: str, release: dict) -> str:
    if len(LOADER.findall(html)) != 1:
        fail('unexpected Flutter bootstrap; refusing to publish unversioned assets')
    base = release_asset_base(release)
    config = {'entrypointBaseUrl': base, 'assetBase': base, 'canvasKitBaseUrl': f'{base}canvaskit/'}
    # Compact separators: the page must read exactly as the website's JSON.stringify wrote it.
    return LOADER.sub(f"_flutter.loader.load({json.dumps({'config': config}, separators=(',', ':'))});\n", html)


def main(manifest_path: str, archive_path: str, out_dir: str) -> None:
    release = json.loads(Path(manifest_path).read_text())
    if not (re.fullmatch(r'\d+\.\d+\.\d+', release.get('version', ''))
            and re.fullmatch(r'[a-f0-9]{40}', release.get('sourceCommit', ''))
            and re.fullmatch(r'[a-f0-9]{64}', release.get('sha256', ''))
            and release.get('baseHref') == BASE_HREF):
        fail(f'invalid web release manifest: {manifest_path}')
    if hashlib.sha256(Path(archive_path).read_bytes()).hexdigest() != release['sha256']:
        fail('web archive checksum mismatch')

    out = Path(out_dir)
    shutil.rmtree(out, ignore_errors=True)
    served = out / 'site' / BASE_HREF.strip('/')
    served.mkdir(parents=True)
    with tarfile.open(archive_path, 'r:gz') as bundle:
        for member in bundle.getmembers():
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or not (member.isfile() or member.isdir()):
                fail(f'web archive contains an unsafe entry: {member.name}')
        bundle.extractall(served, filter='data')

    metadata = json.loads((served / 'release.json').read_text())
    index = (served / 'index.html').read_text()
    if (metadata.get('version') != release['version'] or metadata.get('sourceCommit') != release['sourceCommit']
            or metadata.get('baseHref') != BASE_HREF or f'<base href="{BASE_HREF}">' not in index):
        fail('web archive does not match its release manifest')

    entry = configure_release_assets(index, release)
    versioned = served / release_asset_base(release)[len(BASE_HREF):]
    shutil.copytree(served, versioned, ignore=shutil.ignore_patterns('releases'))
    (served / 'index.html').write_text(entry)
    shutil.copy(Path(__file__).with_name('nginx.conf'), out / 'nginx.conf')
    print(f"Prepared Harness web {release['version']} ({release['sourceCommit'][:12]}) in {out}")


if __name__ == '__main__':
    if len(sys.argv) != 4:
        fail('usage: prepare.py <harness-web-release.json> <archive.tar.gz> <out-dir>')
    main(*sys.argv[1:])
