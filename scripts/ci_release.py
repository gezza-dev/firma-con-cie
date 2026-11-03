#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Keep desktop CI binaries in unpublished releases, never in public artifacts.

Only manually dispatched, unmodified GitHub checkouts may write. Final drafts
are bound to one version/commit; staging drafts are bound to one workflow run.
This tool deliberately has no publish operation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile
import time
from urllib.parse import quote
import zipfile

from product_identity import application_version, linux_package_name

ROOT = Path(__file__).resolve().parents[1]
MARKER = '<!-- firma-con-cie-ci: '
AGGREGATES = {'SHA256SUMS.txt'}


def is_provenance(name):
    return name == 'release-provenance.json' or bool(re.fullmatch(r'provenance-[A-Za-z0-9_-]+\.json', name))


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def safe_name(value):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,180}', value) or '..' in value:
        raise ValueError('Unsafe release asset name')
    return value


class GitHub:
    def __init__(self, repository):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('Invalid GitHub repository')
        self.base = 'repos/' + repository

    def api(self, path, method='GET', data=None, upload=None, download=None):
        args = ['gh', 'api', path, '--method', method]
        if method == 'GET':
            args += ['-H', 'Cache-Control: no-cache']
        if data is not None:
            args += ['--input', '-']
        if upload is not None:
            args += ['--input', str(upload), '-H', 'Content-Type: application/octet-stream']
        if download is not None:
            args += ['-H', 'Accept: application/octet-stream']
        # Tokens stay in GH_TOKEN, never in argv, receipts, logs or exceptions.
        with (Path(download).open('wb') if download else tempfile.TemporaryFile()) as output:
            result = subprocess.run(args, input=json.dumps(data).encode() if data is not None else None,
                                    stdout=output, stderr=subprocess.PIPE)
            if result.returncode:
                raise RuntimeError('GitHub API request failed: ' + method + ' ' +
                                   path.split('?', 1)[0] + ' (see repository permissions/service status)')
            if download:
                return None
            output.seek(0)
            raw = output.read()
        return json.loads(raw) if raw else None

    def pages(self, path):
        result = []
        for page in range(1, 1001):
            batch = self.api(path + ('&' if '?' in path else '?') + f'per_page=100&page={page}')
            result.extend(batch)
            if len(batch) < 100:
                return result
        raise RuntimeError('Unexpected GitHub pagination size')

    def releases(self):
        return self.pages(self.base + '/releases')

    def assets(self, release):
        return self.pages(self.base + f'/releases/{release["id"]}/assets')

    def fresh(self, release):
        return self.api(self.base + f'/releases/{release["id"]}')

    def upload(self, release, name, path):
        return self.api('https://uploads.github.com/' + self.base +
                        f'/releases/{release["id"]}/assets?name=' + quote(name, safe=''),
                        'POST', upload=path)

    def download(self, asset, destination):
        self.api(self.base + f'/releases/assets/{asset["id"]}', download=destination)

    def delete_asset(self, asset):
        self.api(self.base + f'/releases/assets/{asset["id"]}', 'DELETE')


def context(root=ROOT, environment=None):
    env = os.environ if environment is None else environment
    if env.get('GITHUB_EVENT_NAME') != 'workflow_dispatch' or env.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Release writes require a manually dispatched GitHub Actions run')
    commit = env.get('GITHUB_SHA', '')
    run = env.get('GITHUB_RUN_ID', '')
    if not re.fullmatch('[a-f0-9]{40}', commit) or not run.isdigit():
        raise ValueError('Invalid workflow commit/run identity')
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    if actual != commit:
        raise ValueError('Checkout differs from the dispatched commit')
    dirty = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'],
                                    cwd=root, text=True).strip()
    if dirty:
        raise ValueError('Tracked source files changed after checkout')
    return dict(schema=1, commit=commit, version=application_version(root), run=run)


def binding(ctx, staging):
    value = {key: ctx[key] for key in ('schema', 'commit', 'version')}
    if staging:
        value['run'] = ctx['run']
    return value


def tag_for(ctx, staging=False, metadata=False):
    if staging and metadata:
        raise ValueError('Choose either runtime staging or metadata storage')
    if metadata:
        return 'ci-metadata-v' + ctx['version']
    return 'ci-staging-' + ctx['run'] if staging else 'v' + ctx['version']


def check_release(release, ctx, staging=False, metadata=False):
    if not release.get('draft'):
        raise ValueError('Version already published: existing releases are never changed; increment pubspec.yaml')
    markers = re.findall(re.escape(MARKER) + r'(.+?) -->', release.get('body') or '')
    if (len(markers) != 1 or json.loads(markers[0]) != binding(ctx, staging)
            or release['tag_name'] != tag_for(ctx, staging, metadata)
            or release['target_commitish'] != ctx['commit']):
        raise ValueError('Draft belongs to another commit or is not managed by desktop CI')
    return release


def ensure_draft(gh, ctx, staging=False, create=True, metadata=False):
    tag = tag_for(ctx, staging, metadata)
    matches = [r for r in gh.releases() if r['tag_name'] == tag]
    if len(matches) > 1:
        raise ValueError('Duplicate drafts for this version: resolve them before compiling')
    if matches:
        release = check_release(matches[0], ctx, staging, metadata)
        if not staging and not metadata:
            check_tag(gh, ctx)
        return release
    if not create:
        raise ValueError('Expected CI draft is missing')
    if not staging and not metadata:
        check_tag(gh, ctx)
    note = ('Internal CI provenance. Do not publish this metadata release.' if metadata else
            'Temporary private CI transfers and diagnostics. Do not publish this staging release.'
            if staging else 'Builds are being collected. Publication is manual. Verify all targets, '
            'corresponding sources, checksums and hardware test results before publishing.')
    body = note + '\n\nSource commit: `' + ctx['commit'] + '`\n\n' + MARKER + \
        json.dumps(binding(ctx, staging), sort_keys=True) + ' -->\n'
    data = dict(tag_name=tag, target_commitish=ctx['commit'], draft=True, prerelease=False,
                make_latest='false', name=('CI metadata ' + ctx['version'] if metadata else 'CI staging ' + ctx['run'] if staging else
                                          'Firma con CIE ' + ctx['version']), body=body)
    # GitHub may reject simultaneous creation by another platform. Re-read the
    # winner and validate its binding; never silently adopt a different commit.
    try:
        created = gh.api(gh.base + '/releases', 'POST', data=data)
    except RuntimeError:
        for delay in (1, 2, 4):
            time.sleep(delay)
            matches = [r for r in gh.releases() if r['tag_name'] == tag]
            if len(matches) == 1:
                return check_release(matches[0], ctx, staging, metadata)
        raise
    # The POST response is authoritative. The releases list can lag behind a
    # successful create, so do not immediately rediscover the new draft there.
    return check_release(created, ctx, staging, metadata)


def check_tag(gh, ctx):
    """An already-created Git tag must resolve to this exact source commit."""
    ref = 'refs/tags/' + tag_for(ctx)
    references = gh.api(gh.base + '/git/matching-refs/tags/' + tag_for(ctx))
    exact = [r for r in references if r['ref'] == ref]
    if not exact:
        return
    obj = exact[0]['object']
    for _ in range(8):
        if obj['type'] == 'commit':
            if obj['sha'] != ctx['commit']:
                raise ValueError('Existing version tag points to another commit')
            return
        if obj['type'] != 'tag':
            break
        obj = gh.api(gh.base + '/git/tags/' + obj['sha'])['object']
    raise ValueError('Version tag does not resolve to a commit')


def put_asset(gh, release, ctx, name, path, staging=False, metadata=False):
    safe_name(name)
    if is_provenance(name) and not metadata:
        raise ValueError('Provenance JSON belongs only in private CI metadata storage')
    check_release(gh.fresh(release), ctx, staging, metadata)
    digest = sha(path)
    previous = [a for a in gh.assets(release) if a['name'] == name]
    if len(previous) > 1:
        raise ValueError('Duplicate asset name')
    if previous and previous[0].get('digest') == 'sha256:' + digest:
        return previous[0]
    if previous:
        check_release(gh.fresh(release), ctx, staging, metadata)
        gh.delete_asset(previous[0])
    check_release(gh.fresh(release), ctx, staging, metadata)
    try:
        asset = gh.upload(release, name, path)
    except RuntimeError:
        # Idempotent concurrent source upload, or a lost upload response.
        found = [a for a in gh.assets(release) if a['name'] == name]
        if len(found) != 1 or found[0].get('digest') != 'sha256:' + digest:
            raise
        asset = found[0]
    if asset.get('size') != path.stat().st_size or asset.get('digest') != 'sha256:' + digest:
        raise ValueError('Uploaded asset size/digest differs from local bytes')
    return asset


def transfer_pack(directory, archive, ctx):
    directory = directory.resolve(strict=True)
    files = sorted(p for p in directory.rglob('*') if p.is_file())
    if not files:
        raise ValueError('Empty CI transfer')
    if any(p.is_symlink() for p in directory.rglob('*')):
        raise ValueError('CI transfers must contain regular files, not symbolic links')
    manifest = dict(binding(ctx, True), files={p.relative_to(directory).as_posix():sha(p) for p in files})
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=1) as output:
        for path in files:
            output.write(path, 'payload/' + path.relative_to(directory).as_posix())
        output.writestr('transfer.json', json.dumps(manifest, sort_keys=True))


def transfer_unpack(archive, destination, ctx):
    if destination.exists():
        raise ValueError('Use a fresh transfer destination')
    with zipfile.ZipFile(archive) as source:
        members = source.infolist()
        names = [m.filename for m in members]
        if len(names) != len(set(names)) or sum(m.file_size for m in members) > 8 * 1024**3:
            raise ValueError('Unexpected transfer archive')
        manifest = json.loads(source.read('transfer.json'))
        if any(manifest.get(key) != value for key, value in binding(ctx, True).items()):
            raise ValueError('Transfer belongs to a different run/commit/version')
        expected = {'payload/' + name for name in manifest['files']} | {'transfer.json'}
        if set(names) != expected:
            raise ValueError('Transfer inventory mismatch')
        for name in manifest['files']:
            path = PurePosixPath(name)
            info = source.getinfo('payload/' + name)
            if (path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name
                    or any(part in ('', '.', '..') for part in name.split('/'))
                    or (info.external_attr >> 16) & 0o170000 not in (0, 0o100000)):
                raise ValueError('Unsafe transfer member')
        destination.mkdir(parents=True)
        try:
            for name, digest in manifest['files'].items():
                path = destination/name
                path.parent.mkdir(parents=True, exist_ok=True)
                with source.open('payload/' + name) as src, path.open('wb') as dst:
                    shutil.copyfileobj(src, dst)
                if sha(path) != digest:
                    raise ValueError('Transfer file checksum mismatch')
                mode = source.getinfo('payload/' + name).external_attr >> 16
                path.chmod(mode & 0o777 or 0o644)
        except BaseException:
            shutil.rmtree(destination)
            raise


def transfer(gh, ctx, name, directory, receive=False):
    safe_name(name)
    release = ensure_draft(gh, ctx, staging=True, create=not receive)
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary)/(name + '.zip')
        if receive:
            assets = [a for a in gh.assets(release) if a['name'] == archive.name]
            if len(assets) != 1:
                raise ValueError('CI transfer missing; re-run its producer job too')
            gh.download(assets[0], archive)
            if assets[0].get('digest') != 'sha256:' + sha(archive):
                raise ValueError('Downloaded transfer checksum mismatch')
            transfer_unpack(archive, directory, ctx)
        else:
            transfer_pack(directory, archive, ctx)
            put_asset(gh, release, ctx, archive.name, archive, staging=True)


def package_files(target, root=ROOT):
    """Explicit publishable outputs; raw app trees/upgrade fixtures stay private."""
    safe_name(target)
    if target == 'macos-universal':
        folder, patterns = root/'dist/macos', ('*.dmg',)
    elif target in ('windows-x64', 'windows-arm64'):
        folder, patterns = root/('dist/' + target + '/Setup'), ('*_setup.exe',)
    elif re.fullmatch('linux-(x64|arm64)-(deb|appimage)', target):
        folder = root/('dist/' + target)
        patterns = ('*.deb',) if target.endswith('-deb') else ('*.AppImage',)
    elif target in ('linux-fedora-x64', 'linux-fedora-arm64', 'linux-arch-x64'):
        folder = root/('dist/' + target)
        patterns = ('*.rpm',) if '-fedora-' in target else ('*.pkg.tar.zst',)
    else:
        raise ValueError('Unknown package target')
    paths = []
    for pattern in patterns:
        matches = sorted(folder.glob(pattern))
        if len(matches) != 1 or not matches[0].is_file() or matches[0].is_symlink():
            raise ValueError('Expected exactly one final output for ' + target + ': ' + pattern)
        paths.extend(matches)
    return paths


def linux_target_name(target, version):
    if target in ('linux-x64-deb', 'linux-arm64-deb'):
        return linux_package_name(version, 'ubuntu', 'amd64' if '-x64-' in target else 'arm64', 'deb')
    if target in ('linux-x64-appimage', 'linux-arm64-appimage'):
        return linux_package_name(version, 'ubuntu', 'x86_64' if '-x64-' in target else 'aarch64', 'AppImage')
    if target in ('linux-fedora-x64', 'linux-fedora-arm64'):
        return linux_package_name(version, 'fedora', 'x86_64' if target.endswith('-x64') else 'aarch64', 'rpm')
    if target == 'linux-arch-x64':
        return linux_package_name(version, 'arch', 'x86_64', 'pkg.tar.zst')
    raise ValueError('Unknown Linux package target')


def upload_target(gh, ctx, target, receipt, root=ROOT):
    paths = package_files(target, root)
    evidence = json.loads(receipt.read_text())
    if (evidence.get('sourceCommit') != ctx['commit'] or evidence.get('softwareChecksPassed') is not True
            or any(evidence.get(key) for key in ('tlsChecksPending', 'lifecycleChecksPending'))):
        raise ValueError('Build receipt is incomplete or belongs to a different commit')
    if target == 'macos-universal' and not all(evidence.get(k) is True for k in ('notarized', 'developerIdSigned')):
        raise ValueError('macOS packages require Developer ID and notarization')
    architecture = ('universal' if target == 'macos-universal' else
                    next(cpu for cpu in ('x64', 'arm64') if cpu in target.split('-')))
    if evidence.get('architecture') != architecture or evidence.get('version', ctx['version']) != ctx['version']:
        raise ValueError('Build receipt architecture/version mismatch')
    for path in paths:
        if target.startswith('linux-') and path.name != linux_target_name(target, ctx['version']):
            raise ValueError('Linux package filename must identify its distribution and architecture')
        system = 'macOS' if target == 'macos-universal' else target.split('-')[0]
        if not re.search(r'(^|[_-])' + system + r'([_.-]|$)', path.name):
            raise ValueError('Package filename must identify its destination operating system')
        if not re.search(r'[_-]' + re.escape(ctx['version']) + r'[_-]', path.name):
            raise ValueError('Package filename does not match this application version')
        if target.startswith('windows-'):
            result = json.loads((path.parent/'package-result.json').read_text())
            digest = result['sha256']
            if result['bytes'] != path.stat().st_size or result.get('sourceCommit') != ctx['commit']:
                raise ValueError('Installer size/commit differs from packaging receipt')
        else:
            digest = evidence.get('artifacts', {}).get(path.relative_to(root).as_posix())
        if digest != sha(path):
            raise ValueError('Package bytes differ from the validated build receipt')
    release = ensure_draft(gh, ctx, create=False)
    internal = ensure_draft(gh, ctx, metadata=True)
    # Invalidate old completion evidence before updating any bytes. Each target
    # has its own names; aggregate metadata is written only by the serialized job.
    manifest_name = 'provenance-' + target + '.json'
    for asset in gh.assets(internal):
        if asset['name'] == manifest_name:
            check_release(gh.fresh(internal), ctx, metadata=True)
            gh.delete_asset(asset)
    records = {}
    for path in paths:
        put_asset(gh, release, ctx, path.name, path)
        records[path.name] = dict(sha256=sha(path), bytes=path.stat().st_size)
    manifest = dict(binding(ctx, False), target=target, run=ctx['run'],
                    artifacts=records, softwareChecksPassed=True, hardwareValidated=False,
                    releasePublished=False)
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary)
        checksums = folder/('SHA256SUMS-' + target + '.txt')
        checksums.write_text(''.join(v['sha256']+'  '+k+'\n' for k,v in sorted(records.items())))
        metadata = folder/manifest_name
        metadata.write_text(json.dumps(manifest, indent=2)+'\n')
        put_asset(gh, release, ctx, checksums.name, checksums)
        put_asset(gh, internal, ctx, manifest_name, metadata, metadata=True)
    print('Packages uploaded to unpublished draft: ' + release['html_url'])


def upload_sources(gh, ctx):
    from ci_release_sources import prepare
    release = ensure_draft(gh, ctx, create=False)
    internal = ensure_draft(gh, ctx, metadata=True)
    manifest_name = 'provenance-sources.json'
    with tempfile.TemporaryDirectory() as temporary:
        migrate_provenance(gh, ctx, release, internal, Path(temporary))
    private_inventory = {a['name']: a for a in gh.assets(internal)}
    inventory = {a['name']:a for a in gh.assets(release)}
    if manifest_name in private_inventory:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/manifest_name
            gh.download(private_inventory[manifest_name], path)
            if private_inventory[manifest_name].get('digest') != 'sha256:' + sha(path):
                raise ValueError('Source metadata checksum mismatch')
            value = json.loads(path.read_text())
        if (all(value.get(k) == v for k,v in binding(ctx, False).items())
                and value.get('softwareChecksPassed') is True and value.get('target') == 'sources'
                and len(value.get('artifacts', {})) == 3
                and all(inventory.get(name, {}).get('digest') == 'sha256:' + item['sha256']
                        and inventory[name]['size'] == item['bytes']
                        for name,item in value['artifacts'].items())):
            print('Verified corresponding source archives are already in the draft.')
            return
        raise ValueError('Existing source batch is incomplete or has a different identity')
    with tempfile.TemporaryDirectory(prefix='firma-cie-ci-sources-') as temporary:
        folder = Path(temporary)
        paths = prepare(ROOT, folder, ctx['version'])
        records = {}
        for path in paths:
            put_asset(gh, release, ctx, path.name, path)
            records[path.name] = dict(sha256=sha(path), bytes=path.stat().st_size)
        metadata = folder/manifest_name
        metadata.write_text(json.dumps(dict(binding(ctx, False), target='sources', artifacts=records,
            softwareChecksPassed=True, releasePublished=False), indent=2)+'\n')
        sums = folder/'SHA256SUMS-sources.txt'
        sums.write_text(''.join(v['sha256']+'  '+k+'\n' for k,v in sorted(records.items())))
        put_asset(gh, release, ctx, sums.name, sums)
        put_asset(gh, internal, ctx, manifest_name, metadata, metadata=True)


def migrate_provenance(gh, ctx, release, internal, folder):
    """Preserve old draft metadata privately before removing public-facing copies."""
    legacy = [a for a in gh.assets(release) if is_provenance(a['name'])]
    for asset in legacy:
        path = folder/safe_name(asset['name'])
        gh.download(asset, path)
        if asset.get('digest') != 'sha256:' + sha(path):
            raise ValueError('Legacy metadata checksum mismatch')
        data = json.loads(path.read_text())
        if any(data.get(k) != v for k,v in binding(ctx, False).items()):
            raise ValueError('Legacy metadata belongs to another commit')
        previous = [a for a in gh.assets(internal) if a['name'] == asset['name']]
        if previous and asset['name'] == 'release-provenance.json':
            continue  # The aggregate is regenerated from checked target manifests.
        if previous and previous[0].get('digest') != asset.get('digest'):
            raise ValueError('Conflicting private and legacy metadata')
        put_asset(gh, internal, ctx, asset['name'], path, metadata=True)
    return legacy


def aggregate(gh, ctx):
    release = ensure_draft(gh, ctx, create=False)
    internal = ensure_draft(gh, ctx, metadata=True)
    manifests, records = [], {}
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary)
        legacy = migrate_provenance(gh, ctx, release, internal, folder)
        assets = [a for a in gh.assets(release) if not is_provenance(a['name'])]
        inventory = {a['name']:a for a in assets}
        for asset in gh.assets(internal):
            if not asset['name'].startswith('provenance-') or not is_provenance(asset['name']):
                continue
            path = folder/safe_name(asset['name'])
            gh.download(asset, path)
            if asset.get('digest') != 'sha256:' + sha(path):
                raise ValueError('Target metadata checksum mismatch')
            data = json.loads(path.read_text())
            if any(data.get(k) != v for k,v in binding(ctx, False).items()):
                raise ValueError('Target metadata belongs to another commit')
            if not data.get('softwareChecksPassed'):
                raise ValueError('Incomplete target metadata')
            if asset['name'] != 'provenance-' + safe_name(data['target']) + '.json':
                raise ValueError('Target metadata filename mismatch')
            for name, value in data['artifacts'].items():
                remote = inventory.get(name, {})
                if (remote.get('digest') != 'sha256:' + value['sha256'] or remote.get('size') != value['bytes']
                        or name in records):
                    raise ValueError('Incomplete, conflicting or outdated target inventory')
                records[name] = value
            manifests.append(data)
        # Every public-facing file must be a validated package, source or checksum.
        expected_sums = {'SHA256SUMS-' + data['target'] + '.txt' for data in manifests}
        covered = set(records) | expected_sums | AGGREGATES
        if set(inventory) - covered or not manifests or not expected_sums <= set(inventory):
            raise ValueError('Unfinished target upload; re-run draft metadata after producers finish')
        for asset in assets:
            if asset['name'] not in AGGREGATES:
                digest = asset.get('digest', '')
                if not re.fullmatch('sha256:[a-f0-9]{64}', digest):
                    raise ValueError('Asset lacks a verified digest')
                records.setdefault(asset['name'], dict(sha256=digest[7:], bytes=asset['size']))
        metadata = folder/'release-provenance.json'
        metadata.write_text(json.dumps(dict(binding(ctx, False), targets=manifests,
            artifacts=records, releasePublished=False, manualReviewRequired=True), indent=2)+'\n')
        put_asset(gh, internal, ctx, metadata.name, metadata, metadata=True)
        for asset in legacy:
            check_release(gh.fresh(release), ctx)
            gh.delete_asset(asset)
        sums = folder/'SHA256SUMS.txt'
        sums.write_text(''.join(v['sha256']+'  '+k+'\n' for k,v in sorted(records.items())))
        put_asset(gh, release, ctx, sums.name, sums)
    print('Unpublished draft checksums updated; JSON metadata kept private: ' + release['html_url'])


def diagnostics(gh, ctx, name, paths):
    # Diagnostics also remain private; source paths/installer fixtures in reports
    # must not accidentally become public downloadable Actions artifacts.
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary)/'reports'
        folder.mkdir()
        for index, path in enumerate(paths):
            if path.is_dir() and not path.is_symlink():
                shutil.copytree(path, folder/(str(index)+'-'+path.name), symlinks=True)
            elif path.is_file() and not path.is_symlink():
                shutil.copy2(path, folder/(str(index)+'-'+path.name))
        # Symlinks and signing material are excluded, including on error paths.
        for path in sorted(folder.rglob('*'), reverse=True):
            if path.is_symlink() or path.suffix.lower() in ('.p12', '.p8', '.key', '.keychain', '.keychain-db'):
                path.unlink()
        (folder/'workflow.json').write_text(json.dumps(dict(binding(ctx, True), run=ctx['run']))+'\n')
        transfer(gh, ctx, 'diagnostics-' + safe_name(name) + '-' + os.environ.get('GITHUB_RUN_ATTEMPT', '1'), folder)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('prepare')
    sub.add_parser('stage')
    sub.add_parser('sources')
    sub.add_parser('aggregate')
    for action in ('send', 'receive'):
        p = sub.add_parser(action)
        p.add_argument('--name', required=True)
        p.add_argument('--directory', type=Path, required=True)
    p = sub.add_parser('upload')
    p.add_argument('--target', required=True)
    p.add_argument('--receipt', type=Path, required=True)
    p = sub.add_parser('diagnostics')
    p.add_argument('--name', required=True)
    p.add_argument('paths', nargs='+', type=Path)
    args = parser.parse_args()
    ctx = context()
    gh = GitHub(os.environ['GITHUB_REPOSITORY'])
    if args.action == 'prepare':
        release = ensure_draft(gh, ctx)
        ensure_draft(gh, ctx, staging=True)
        print('Unpublished version draft: ' + release['html_url'])
    elif args.action == 'stage':
        ensure_draft(gh, ctx, staging=True)
    elif args.action == 'aggregate':
        aggregate(gh, ctx)
    elif args.action == 'sources':
        upload_sources(gh, ctx)
    elif args.action == 'upload':
        upload_target(gh, ctx, args.target, args.receipt)
    elif args.action == 'diagnostics':
        diagnostics(gh, ctx, args.name, args.paths)
    else:
        transfer(gh, ctx, args.name, args.directory, receive=args.action == 'receive')


if __name__ == '__main__':
    main()
