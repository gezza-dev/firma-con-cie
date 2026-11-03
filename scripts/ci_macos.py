#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Universal macOS CI: isolated signing keychain, CTK, Developer ID and notarization."""
import argparse
import base64
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shlex
import subprocess
import tempfile

from ci_desktop_common import ROOT, flutter_checks, java_tools, python, receipt, run
from product_identity import application_version, macos_image_name
from macos_signing import MacCodeSigner

SECRET_NAMES = ('MACOS_CERTIFICATE_P12_BASE64', 'MACOS_CERTIFICATE_PASSWORD',
                'MACOS_SIGNING_IDENTITY', 'MACOS_TEAM_ID',
                'MACOS_NOTARY_KEY_P8_BASE64', 'MACOS_NOTARY_KEY_ID', 'MACOS_NOTARY_ISSUER_ID',
                'MACOS_NOTARY_APPLE_ID', 'MACOS_NOTARY_PASSWORD')


def signing_configuration(environment):
    missing = [key for key in SECRET_NAMES[:4] if not environment.get(key)]
    if missing:
        raise ValueError('Configure the GitHub Actions secrets: ' + ', '.join(missing))
    if not re.fullmatch('[A-Z0-9]{10}', environment['MACOS_TEAM_ID']):
        raise ValueError('Invalid MACOS_TEAM_ID')
    identity = environment['MACOS_SIGNING_IDENTITY']
    if not (identity.startswith('Developer ID Application:') or re.fullmatch('[a-fA-F0-9]{40}', identity)):
        raise ValueError('A Developer ID Application signing identity is required')
    if any(environment.get(key) for key in SECRET_NAMES[4:7]):
        required = ('MACOS_NOTARY_KEY_P8_BASE64', 'MACOS_NOTARY_KEY_ID')
    else:
        required = ('MACOS_NOTARY_APPLE_ID', 'MACOS_NOTARY_PASSWORD')
    if any(not environment.get(key) for key in required):
        raise ValueError('Configure notarization secrets: an App Store Connect API key and key ID, '
                         'or MACOS_NOTARY_APPLE_ID and MACOS_NOTARY_PASSWORD (app-specific password)')
    return {key:environment[key] for key in SECRET_NAMES if environment.get(key)}


def confidential(*command):
    # security/notary credentials must never enter the normal command logger
    # or exception rendering (CalledProcessError includes the command line).
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
    if result.returncode:
        operation = str(command[1]) if str(command[0]) == 'security' else 'notarytool'
        raise RuntimeError('Apple operation '+operation+' failed (exit '+str(result.returncode)+
                           '); check the configured credentials and signing identity')
    return result.stdout


class SigningSession:
    def __init__(self, configuration, temporary_root):
        self.configuration = configuration
        self.folder = Path(tempfile.mkdtemp(prefix='firma-cie-signing-', dir=temporary_root))
        self.folder.chmod(0o700)
        self.keychain = self.folder/'build.keychain-db'
        self.original_keychains = None

    def __enter__(self):
        try:
            password = secrets.token_urlsafe(40)
            self.original_keychains = shlex.split(confidential('security', 'list-keychains', '-d', 'user'))
            state = self.folder/'state.json'
            state.touch(mode=0o600)
            state.write_text(json.dumps(self.original_keychains))
            confidential('security', 'create-keychain', '-p', password, self.keychain)
            confidential('security', 'set-keychain-settings', '-lut', '21600', self.keychain)
            confidential('security', 'unlock-keychain', '-p', password, self.keychain)
            confidential('security', 'list-keychains', '-d', 'user', '-s', *self.original_keychains, self.keychain)
            cert = self.folder/'identity.p12'
            key = self.folder/'notary.p8'
            materials = [(cert, 'MACOS_CERTIFICATE_P12_BASE64')]
            if self.configuration.get('MACOS_NOTARY_KEY_P8_BASE64'):
                materials.append((key, 'MACOS_NOTARY_KEY_P8_BASE64'))
            for target, name in materials:
                try:
                    data = base64.b64decode(''.join(self.configuration[name].split()), validate=True)
                    if not data:
                        raise ValueError('Empty secret')
                except (ValueError, base64.binascii.Error):
                    raise ValueError('Invalid base64 encoding in '+name) from None
                target.touch(mode=0o600, exist_ok=False)
                target.write_bytes(data)
            confidential('security', 'import', cert, '-k', self.keychain, '-P',
                         self.configuration['MACOS_CERTIFICATE_PASSWORD'], '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            confidential('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, self.keychain)
            if key.exists():
                credentials = ['--key', key, '--key-id', self.configuration['MACOS_NOTARY_KEY_ID']]
                if self.configuration.get('MACOS_NOTARY_ISSUER_ID'):
                    credentials += ['--issuer', self.configuration['MACOS_NOTARY_ISSUER_ID']]
            else:
                credentials = ['--apple-id', self.configuration['MACOS_NOTARY_APPLE_ID'],
                               '--password', self.configuration['MACOS_NOTARY_PASSWORD'],
                               '--team-id', self.configuration['MACOS_TEAM_ID']]
            confidential('xcrun', 'notarytool', 'store-credentials', 'ci-notary',
                         *credentials, '--keychain', self.keychain)
            cert.unlink()
            key.unlink(missing_ok=True)
            return self
        except BaseException:
            self.close()
            raise

    def close(self):
        # Restore the runner's original search list. Only this session's own
        # keychain and files are removed, even after import/notarization fails.
        try:
            if self.original_keychains is not None:
                confidential('security', 'list-keychains', '-d', 'user', '-s', *self.original_keychains)
        finally:
            if self.keychain.exists():
                subprocess.run(['security', 'delete-keychain', str(self.keychain)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for name in ('identity.p12', 'notary.p8', 'build.keychain-db', 'state.json'):
                (self.folder/name).unlink(missing_ok=True)
            # rmdir cannot remove unrelated files or recurse outside our folder.
            if self.folder.exists():
                try:
                    self.folder.rmdir()
                except OSError:
                    pass

    def __exit__(self, *_):
        self.close()

    def notarize(self, artifact):
        raw = confidential('xcrun', 'notarytool', 'submit', artifact, '--keychain-profile', 'ci-notary',
                           '--keychain', self.keychain, '--wait', '--timeout', '30m', '--output-format', 'json')
        result = json.loads(raw)
        if result.get('status') != 'Accepted':
            raise RuntimeError('Apple notarization was not accepted')
        return {'status':result['status'], 'id':result['id']}


def cleanup(temporary_root):
    root = Path(temporary_root).resolve()
    for folder in root.glob('firma-cie-signing-*'):
        if folder.is_symlink() or not folder.is_dir() or folder.resolve().parent != root:
            continue
        session = object.__new__(SigningSession)
        session.folder = folder
        session.keychain = folder/'build.keychain-db'
        session.original_keychains = None
        state = folder/'state.json'
        if state.is_file() and not state.is_symlink():
            value = json.loads(state.read_text())
            if isinstance(value, list) and all(isinstance(p, str) for p in value):
                session.original_keychains = value
        session.close()


def build():
    configuration = signing_configuration(os.environ)
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('macOS Universal CI requires the Apple Silicon macOS runner')
    version = subprocess.check_output(['xcodebuild', '-version'], text=True)
    if not re.search(r'Xcode (?:2[6-9]|[3-9][0-9])\.', version):
        raise ValueError('Xcode 26 or newer is required by the icon catalog')
    work = ROOT/'.build/ci-macos'
    work.mkdir(parents=True)
    reports = ROOT/'reports/macos'
    reports.mkdir(parents=True, exist_ok=True)
    flutter_checks()
    for cpu in ('arm64', 'x86_64'):
        python('build_portable_dependencies.py', '--arch', cpu, '--jobs', '2')
    prefix = ROOT/'.build/dependencies/macos-universal/prefix'
    python('merge_macos_dependencies.py', '--arm64', ROOT/'.build/dependencies/macos-arm64/prefix',
           '--x86-64', ROOT/'.build/dependencies/macos-x86_64/prefix', '--output', prefix)
    base = work/'native-base'
    python('build_native.py', '--system', 'macos', '--dependency-prefix', prefix,
           '--architectures', 'arm64;x86_64', '--jobs', '2', '--output', base)
    java, maven, cache = java_tools('macos', 'arm64', work)
    runtime = ROOT/'native/runtime/macos'
    python('build_ltv.py', '--system', 'macos', '--java-home', java, '--maven', maven,
           '--base-runtime', base, '--output', runtime, '--tools-cache', cache)
    python('smoke_native.py', '--runtime', runtime, '--report', reports/'native.json')
    python('test_ltv.py', '--runtime', runtime, '--report', reports/'ltv.json')
    output = ROOT/'dist/macos'
    output.mkdir(parents=True)
    with SigningSession(configuration, os.environ['RUNNER_TEMP']) as session:
        identity = configuration['MACOS_SIGNING_IDENTITY']
        extension = work/'web'
        python('build_web_macos.py', '--runtime', runtime, '--output', extension,
               '--identity', identity, '--team-id', configuration['MACOS_TEAM_ID'], '--developer-id')
        # Both build and package paths are explicit: never use developer-local
        # defaults or a host keychain profile stored on a personal Mac.
        destination = work/'signed'
        workspace = Path(tempfile.mkdtemp(prefix='firma-cie-macos-workspace-', dir='/private/tmp'))
        python('build_macos.py', '--runtime', runtime, '--identity', identity,
               '--developer-id', '--destination', destination, '--build-workspace', workspace,
               '--web-extension', extension/'CIEPrototypeToken.appex')
        app = destination/'Firma con CIE.app'
        submission = work/'notarize-app.zip'
        run('ditto', '-c', '-k', '--keepParent', app, submission)
        app_notary = session.notarize(submission)
        run('xcrun', 'stapler', 'staple', app)
        run('xcrun', 'stapler', 'validate', app)
        run('spctl', '--assess', '--type', 'execute', app)
        dmg = output/macos_image_name(application_version())
        python('package_macos_dmg.py', '--app', app, '--identity', identity, '--developer-id',
               '--output', dmg, '--report', reports/'dmg-before-notarization.json')
        dmg_notary = session.notarize(dmg)
        run('xcrun', 'stapler', 'staple', dmg)
        run('xcrun', 'stapler', 'validate', dmg)
        run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', dmg)
        result = receipt(reports/'result.json', 'macos', 'universal', [dmg],
                         softwareChecksPassed=True, developerIdSigned=True,
                         appNotarization=app_notary, dmgNotarization=dmg_notary,
                         notarized=True)
        (output/'SHA256SUMS').write_text(''.join(digest+'  '+Path(name).name+'\n'
                                             for name,digest in result['artifacts'].items()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check-secrets', 'check-credentials', 'build', 'cleanup'])
    action = parser.parse_args().action
    if action == 'check-secrets':
        signing_configuration(os.environ)
        print('Required macOS signing and notarization secrets are configured.')
    elif action == 'cleanup':
        cleanup(os.environ['RUNNER_TEMP'])
    elif action == 'check-credentials':
        configuration = signing_configuration(os.environ)
        with SigningSession(configuration, os.environ['RUNNER_TEMP']):
            MacCodeSigner(configuration['MACOS_SIGNING_IDENTITY'], developer_id=True)
        print('Developer ID identity and notarization credentials verified; temporary keychain removed.')
    else:
        build()
