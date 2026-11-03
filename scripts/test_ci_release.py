#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Synthetic GitHub integration: no live releases, binaries, secrets or cards."""
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import ci_release as ci
import ci_release_sources as sources

CTX = dict(schema=1, commit='a'*40, version='9.8.7', run='123')


class FakeGitHub:
    base = 'repos/example/project'

    def __init__(self):
        self.items = []
        self.payloads = {}
        self.deleted = []
        self.tag = None

    def api(self, path, method='GET', data=None):
        if '/git/matching-refs/' in path:
            return [] if not self.tag else [dict(ref='refs/tags/v'+CTX['version'], object=self.tag)]
        if method == 'POST' and path == self.base+'/releases':
            value = dict(data, id=len(self.items)+1, html_url='https://github.com/example/draft')
            self.items.append(value)
            return copy.deepcopy(value)
        raise AssertionError((path, method))

    def releases(self):
        return copy.deepcopy(self.items)

    def assets(self, release):
        return [copy.deepcopy(v[0]) for v in self.payloads.values() if v[0]['release'] == release['id']]

    def fresh(self, release):
        return copy.deepcopy(next(r for r in self.items if r['id'] == release['id']))

    def upload(self, release, name, path):
        data = path.read_bytes()
        asset = dict(id=max(self.payloads, default=0)+1, name=name, release=release['id'],
                     digest='sha256:'+hashlib.sha256(data).hexdigest(), size=len(data))
        self.payloads[asset['id']] = (asset, data)
        return copy.deepcopy(asset)

    def download(self, asset, path):
        path.write_bytes(self.payloads[asset['id']][1])

    def delete_asset(self, asset):
        self.deleted.append(asset['id'])
        del self.payloads[asset['id']]


class DraftReleaseTests(unittest.TestCase):
    def test_creation_is_unpublished_pinned_and_idempotent(self):
        gh = FakeGitHub()
        first = ci.ensure_draft(gh, CTX)
        self.assertEqual(first['id'], ci.ensure_draft(gh, dict(CTX, run='456'))['id'])
        self.assertTrue(first['draft'])
        self.assertEqual(first['make_latest'], 'false')
        self.assertEqual(first['target_commitish'], CTX['commit'])
        self.assertEqual(len(gh.items), 1)

    def test_creation_succeeds_even_if_list_visibility_lags_behind_post(self):
        gh=FakeGitHub()
        with patch.object(gh,'releases',return_value=[]):
            release=ci.ensure_draft(gh,CTX)
        self.assertTrue(release['draft'])
        self.assertEqual(release['id'],gh.items[0]['id'])
        self.assertEqual(len(gh.items),1)

    def test_published_release_is_never_modified(self):
        gh = FakeGitHub()
        ci.ensure_draft(gh, CTX)
        gh.items[0]['draft'] = False
        before = copy.deepcopy(gh.items)
        with self.assertRaisesRegex(ValueError, 'already published'):
            ci.ensure_draft(gh, CTX)
        self.assertEqual(gh.items, before)
        self.assertFalse(gh.payloads)

    def test_different_source_commit_unmanaged_and_duplicate_drafts_are_rejected(self):
        for mutation in ('commit', 'body', 'duplicate'):
            gh = FakeGitHub()
            ci.ensure_draft(gh, CTX)
            ctx = dict(CTX)
            if mutation == 'commit':ctx['commit'] = 'b'*40
            elif mutation == 'body':gh.items[0]['body'] = 'hand-written draft'
            else:gh.items.append(copy.deepcopy(gh.items[0]))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                ci.ensure_draft(gh, ctx)
            self.assertFalse(gh.payloads)

    def test_existing_tag_cannot_point_to_another_commit(self):
        gh = FakeGitHub()
        gh.tag = dict(type='commit', sha='b'*40)
        with self.assertRaisesRegex(ValueError, 'tag points'):
            ci.ensure_draft(gh, CTX)
        self.assertFalse(gh.items)
        gh.tag['sha'] = CTX['commit']
        self.assertTrue(ci.ensure_draft(gh, CTX)['draft'])

    def test_staging_is_bound_to_run_and_is_separate_from_final_draft(self):
        gh = FakeGitHub()
        final = ci.ensure_draft(gh, CTX)
        stage = ci.ensure_draft(gh, CTX, staging=True)
        self.assertNotEqual(final['id'], stage['id'])
        self.assertTrue(stage['tag_name'].startswith('ci-staging-'))
        self.assertEqual(ci.binding(CTX, True)['run'], '123')
        with self.assertRaises(ValueError):
            ci.check_release(stage, dict(CTX, run='456'), staging=True)

    def test_upload_rechecks_draft_and_reuses_identical_bytes(self):
        gh = FakeGitHub()
        release = ci.ensure_draft(gh, CTX)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'synthetic.bin';path.write_bytes(b'synthetic')
            first = ci.put_asset(gh, release, CTX, 'test.bin', path)
            self.assertEqual(ci.put_asset(gh, release, CTX, 'test.bin', path)['id'], first['id'])
            gh.items[0]['draft'] = False
            path.write_bytes(b'changed')
            with self.assertRaises(ValueError):ci.put_asset(gh, release, CTX, 'test.bin', path)
        self.assertFalse(gh.deleted)

    def test_api_failure_never_echoes_token_or_tool_stderr(self):
        from types import SimpleNamespace
        with patch.object(ci.subprocess, 'run', return_value=SimpleNamespace(returncode=1, stderr=b'private-value')):
            with self.assertRaises(RuntimeError) as error:
                ci.GitHub('example/repo').api('repos/example/repo/releases')
        self.assertNotIn('private-value', str(error.exception))

    def test_context_requires_manual_actions_matching_clean_checkout(self):
        env = dict(GITHUB_ACTIONS='true', GITHUB_EVENT_NAME='workflow_dispatch',
                   GITHUB_SHA=CTX['commit'], GITHUB_RUN_ID=CTX['run'])
        with patch.object(ci.subprocess, 'check_output', side_effect=[CTX['commit']+'\n', '']), \
             patch.object(ci, 'application_version', return_value=CTX['version']):
            self.assertEqual(ci.context(environment=env), CTX)
        for event in ('push', 'pull_request', 'pull_request_target'):
            with self.assertRaises(ValueError):ci.context(environment=dict(env, GITHUB_EVENT_NAME=event))
        with patch.object(ci.subprocess, 'check_output', side_effect=[CTX['commit']+'\n',' M pubspec.yaml']), \
             self.assertRaisesRegex(ValueError, 'Tracked source'):
            ci.context(environment=env)

    def test_private_transfer_preserves_hidden_files_and_executable_mode(self):
        gh = FakeGitHub()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);src = root/'input';src.mkdir()
            (src/'.manifest').write_text('hidden')
            binary = src/'runtime';binary.write_bytes(b'synthetic runtime');binary.chmod(0o755)
            ci.transfer(gh, CTX, 'linux-runtime', src)
            ci.transfer(gh, CTX, 'linux-runtime', root/'output', receive=True)
            self.assertEqual((root/'output/.manifest').read_text(), 'hidden')
            self.assertTrue((root/'output/runtime').stat().st_mode & 0o111)
        self.assertEqual(len(gh.items), 1)
        self.assertEqual(gh.items[0]['tag_name'], 'ci-staging-123')

    def test_transfer_refuses_tampering_paths_other_runs_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);src = root/'input';src.mkdir()
            (src/'file').write_text('original')
            archive = root/'transfer.zip'
            ci.transfer_pack(src, archive, CTX)
            with self.assertRaisesRegex(ValueError, 'different run'):
                ci.transfer_unpack(archive, root/'output', dict(CTX, run='999'))
            for name in ('../../escape', '/absolute', 'folder\\escape', 'C:/escape'):
                payload = b'synthetic'
                metadata = dict(ci.binding(CTX, True), files={name:hashlib.sha256(payload).hexdigest()})
                with zipfile.ZipFile(archive, 'w') as output:
                    output.writestr('transfer.json', json.dumps(metadata))
                    output.writestr('payload/'+name, payload)
                with self.subTest(name=name), self.assertRaises(ValueError):
                    ci.transfer_unpack(archive, root/'output', CTX)
                self.assertFalse((root/'output').exists())
            (src/'link').symlink_to(src/'file')
            with self.assertRaisesRegex(ValueError, 'symbolic links'):
                ci.transfer_pack(src, archive, CTX)

    def test_interrupted_transfer_extraction_removes_partial_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);src = root/'input';src.mkdir();(src/'file').write_text('original')
            archive = root/'input.zip';ci.transfer_pack(src, archive, CTX)
            with patch.object(ci, 'sha', return_value='incorrect'), self.assertRaisesRegex(ValueError, 'checksum'):
                ci.transfer_unpack(archive, root/'output', CTX)
            self.assertFalse((root/'output').exists())

    def make_windows(self, root, architecture):
        folder = root/f'dist/windows-{architecture}/Setup';folder.mkdir(parents=True)
        binary = folder/f'firma-con-cie_9.8.7_windows_{architecture}_setup.exe'
        binary.write_bytes(b'synthetic-'+architecture.encode())
        (folder/'Release').mkdir();(folder/'Release/internal.dll').write_bytes(b'not published')
        receipt = root/(architecture+'.json')
        receipt.write_text(json.dumps(dict(sourceCommit=CTX['commit'], softwareChecksPassed=True, architecture=architecture)))
        (folder/'package-result.json').write_text(json.dumps(dict(sha256=ci.sha(binary), bytes=binary.stat().st_size, sourceCommit=CTX['commit'])))
        return receipt, binary

    def test_two_targets_share_one_draft_and_have_consistent_combined_checksums(self):
        gh = FakeGitHub();release = ci.ensure_draft(gh, CTX)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for arch in ('x64','arm64'):
                receipt, binary = self.make_windows(root, arch)
                ci.upload_target(gh, CTX, 'windows-'+arch, receipt, root=root)
            ci.aggregate(gh, CTX)
            assets = {a['name']:a for a in gh.assets(release)}
            metadata = root/'metadata';gh.download(assets['release-provenance.json'], metadata)
            data = json.loads(metadata.read_text())
            self.assertEqual(len(data['targets']), 2)
            self.assertFalse(data['releasePublished'])
            sums = root/'sums';gh.download(assets['SHA256SUMS.txt'], sums)
            for line in sums.read_text().splitlines():
                digest,name = line.split(None, 1)
                self.assertEqual(assets[name]['digest'], 'sha256:'+digest)
            self.assertFalse(any('dll' in name or 'Release' in name for name in assets))
            self.assertTrue(all(r['draft'] for r in gh.items))

    def test_failed_wrong_commit_and_unnotarized_receipts_cannot_upload(self):
        gh = FakeGitHub();ci.ensure_draft(gh, CTX)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);receipt,_ = self.make_windows(root,'x64')
            for evidence in (dict(sourceCommit=CTX['commit'],softwareChecksPassed=False),
                             dict(sourceCommit='b'*40,softwareChecksPassed=True),
                             dict(sourceCommit=CTX['commit'],softwareChecksPassed=True,tlsChecksPending=True)):
                receipt.write_text(json.dumps(evidence))
                with self.assertRaises(ValueError):ci.upload_target(gh, CTX, 'windows-x64',receipt,root)
            folder=root/'dist/macos';folder.mkdir(parents=True)
            (folder/'example.dmg').write_bytes(b'unsigned')
            (folder/'example_universal_app.zip').write_bytes(b'unsigned')
            receipt.write_text(json.dumps(dict(sourceCommit=CTX['commit'],softwareChecksPassed=True)))
            with self.assertRaisesRegex(ValueError, 'notarization'):
                ci.upload_target(gh, CTX, 'macos-universal', receipt, root)
        self.assertFalse(gh.payloads)

    def test_all_macos_and_linux_target_routes_use_their_validated_receipt(self):
        cases = {
            'macos-universal': ('dist/macos', ['firma-con-cie_9.8.7_macOS_universal.dmg']),
            'linux-x64-deb': ('dist/linux-x64-deb', ['firma-con-cie-linux_9.8.7_amd64.deb']),
            'linux-arm64-deb': ('dist/linux-arm64-deb', ['firma-con-cie-linux_9.8.7_arm64.deb']),
            'linux-x64-appimage': ('dist/linux-x64-appimage', ['firma-con-cie-linux-9.8.7-x86_64.AppImage']),
            'linux-arm64-appimage': ('dist/linux-arm64-appimage', ['firma-con-cie-linux-9.8.7-aarch64.AppImage']),
            'linux-fedora-x64': ('dist/linux-fedora-x64', ['firma-con-cie-linux-9.8.7-1.fc44.x86_64.rpm']),
            'linux-fedora-arm64': ('dist/linux-fedora-arm64', ['firma-con-cie-linux-9.8.7-1.fc44.aarch64.rpm']),
            'linux-arch-x64': ('dist/linux-arch-x64', ['firma-con-cie-linux-9.8.7-1-x86_64.pkg.tar.zst']),
        }
        gh=FakeGitHub();release=ci.ensure_draft(gh,CTX)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for target,(folder,names) in cases.items():
                paths=[]
                for name in names:
                    path=root/folder/name;path.parent.mkdir(parents=True,exist_ok=True)
                    path.write_bytes(b'synthetic');paths.append(path)
                evidence=dict(sourceCommit=CTX['commit'],softwareChecksPassed=True,version=CTX['version'],
                    architecture='universal' if target=='macos-universal' else 'arm64' if 'arm64' in target else 'x64',
                    developerIdSigned=True,notarized=True,
                    artifacts={p.relative_to(root).as_posix():ci.sha(p) for p in paths})
                receipt=root/'result.json';receipt.write_text(json.dumps(evidence))
                with self.subTest(target=target):ci.upload_target(gh,CTX,target,receipt,root)
            ci.aggregate(gh,CTX)
            metadata=root/'all.json'
            asset=next(a for a in gh.assets(release) if a['name']=='release-provenance.json')
            gh.download(asset,metadata)
            self.assertEqual(len(json.loads(metadata.read_text())['targets']),len(cases))

    def test_aggregate_refuses_partial_batch_and_other_commit(self):
        gh = FakeGitHub();release=ci.ensure_draft(gh, CTX)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);receipt,binary=self.make_windows(root,'x64')
            ci.put_asset(gh, release, CTX, binary.name, binary)
            with self.assertRaisesRegex(ValueError, 'Unfinished'):
                ci.aggregate(gh, CTX)
            ci.upload_target(gh, CTX, 'windows-x64', receipt,root)
            asset=next(a for a in gh.assets(release) if a['name']=='provenance-windows-x64.json')
            data=json.loads(gh.payloads[asset['id']][1]);data['commit']='b'*40
            path=root/'wrong.json';path.write_text(json.dumps(data))
            ci.put_asset(gh,release,CTX,asset['name'],path)
            with self.assertRaisesRegex(ValueError, 'another commit'):
                ci.aggregate(gh,CTX)

    def test_corresponding_sources_use_all_checked_in_common_and_linux_locks(self):
        common,linux=sources.source_inputs(ci.ROOT)
        self.assertEqual(sum(k.startswith('native/') for k in common),12)
        self.assertEqual(sum(k.startswith('java/') for k in common),50)
        self.assertTrue(any(k.startswith('openjdk/') for k in common))
        lock=json.loads((ci.ROOT/'packaging/release/linux-system-sources.lock.json').read_text())
        self.assertEqual(len(linux),sum(len(p['files']) for p in lock['ubuntuSourcePackages'].values()))
        for items in (common,linux):
            for name,item in items.items():
                self.assertNotIn('..',Path(name).parts)
                self.assertRegex(item['sha256'],r'^[a-f0-9]{64}$')

    def test_source_download_requires_locked_bytes_and_digest(self):
        import io
        payload=b'synthetic corresponding source'
        item=dict(url='https://example.invalid/source',bytes=len(payload),
                  sha256=hashlib.sha256(payload).hexdigest())
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'source'
            with patch.object(sources.urllib.request,'urlopen',return_value=io.BytesIO(payload)):
                self.assertEqual(sources.fetch(item,path),(path,item['url']))
            with patch.object(sources.urllib.request,'urlopen',return_value=io.BytesIO(b'tampered')), \
                 self.assertRaisesRegex(ValueError,'checksum/size'):
                sources.fetch(item,path)

    def test_package_changes_after_validation_do_not_reach_draft(self):
        gh=FakeGitHub();ci.ensure_draft(gh,CTX)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);receipt,binary=self.make_windows(root,'x64')
            binary.write_bytes(b'tampered')
            with self.assertRaisesRegex(ValueError,'packaging receipt'):
                ci.upload_target(gh,CTX,'windows-x64',receipt,root)
        self.assertFalse(gh.payloads)

    def test_macos_upload_ignores_app_zip_and_rejects_packages_without_os_name(self):
        gh=FakeGitHub();release=ci.ensure_draft(gh,CTX)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);folder=root/'dist/macos';folder.mkdir(parents=True)
            dmg=folder/'firma-con-cie_9.8.7_macOS_universal.dmg';dmg.write_bytes(b'synthetic DMG')
            (folder/'firma-con-cie_9.8.7_universal_app.zip').write_bytes(b'do not publish')
            receipt=root/'result.json'
            receipt.write_text(json.dumps(dict(sourceCommit=CTX['commit'],softwareChecksPassed=True,
                architecture='universal',version=CTX['version'],developerIdSigned=True,notarized=True,
                artifacts={dmg.relative_to(root).as_posix():ci.sha(dmg)})))
            ci.upload_target(gh,CTX,'macos-universal',receipt,root)
            self.assertEqual([a['name'] for a in gh.assets(release) if a['name'].endswith(('.dmg','.zip'))],[dmg.name])
            old=dmg.with_name('firma-con-cie_9.8.7_universal.dmg');dmg.rename(old)
            with self.assertRaisesRegex(ValueError,'destination operating system'):
                ci.upload_target(gh,CTX,'macos-universal',receipt,root)

    def test_source_upload_can_resume_and_verify_existing_batch(self):
        gh=FakeGitHub();ci.ensure_draft(gh,CTX)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            archives=[]
            for suffix in ('sources','dependency-sources','linux-system-sources'):
                path=root/f'firma-con-cie_9.8.7_{suffix}.zip';path.write_bytes(suffix.encode());archives.append(path)
            with patch.object(sources,'prepare',return_value=archives) as prepare:
                ci.upload_sources(gh,CTX);ci.upload_sources(gh,CTX)
            prepare.assert_called_once()
            ci.aggregate(gh,CTX)

    def test_workflows_have_no_public_binary_artifacts_or_publish_operation(self):
        workflows=ci.ROOT/'.github/workflows'
        for path in workflows.glob('*.yml'):
            text=path.read_text()
            self.assertNotIn('upload-artifact@',text)
            self.assertNotIn('download-artifact@',text)
            self.assertNotIn('actions/cache@',text)
            self.assertNotRegex(text,r'(?m)^  (push|pull_request|pull_request_target):')
            self.assertNotIn('--draft=false',text)
            self.assertNotIn('gh release create',text)
        for name in ('desktop-packages','macos-package','windows-package','linux-package','linux-distributions'):
            text=(workflows/(name+'.yml')).read_text()
            self.assertIn('phase: prepare',text)
            self.assertIn('contents: write',text)
            self.assertIn('draft_metadata:',text)


if __name__=='__main__':
    unittest.main(verbosity=2)
