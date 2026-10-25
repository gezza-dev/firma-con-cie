#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Exercise output staging through the real document portal, without card access.

Requires the test Flatpak installed for the current user, PyGObject and an
explicit directory containing output-staging-tests and no-card-guard.so.
Only a newly created synthetic document receives portal permissions; the grant
is deleted afterwards. The app GUI and its pairing archive are never opened.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

APP_ID = 'it.giancarloezza.FirmaConCIE.Test'


def check(tools, report, probe='output-staging-tests', expect_directory_error=False):
    from gi.repository import Gio, GLib
    tools = tools.resolve(strict=True)
    assert (tools / probe).is_file() and (tools / 'no-card-guard.so').is_file()
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    name, path, interface = ('org.freedesktop.portal.Documents',
                             '/org/freedesktop/portal/documents',
                             'org.freedesktop.portal.Documents')
    doc_id = None
    with tempfile.TemporaryDirectory(prefix='cie-portal-synthetic-') as folder:
        try:
            fd = os.open(folder, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC)
            descriptors = Gio.UnixFDList.new()
            try:
                handle = descriptors.append(fd)
            finally:
                os.close(fd)
            reply, _ = connection.call_with_unix_fd_list_sync(
                name, path, interface, 'AddNamedFull',
                GLib.Variant('(hayusas)', (handle, b'synthetic.pdf\0', 0,
                                           APP_ID, ['read', 'write', 'delete'])),
                GLib.VariantType.new('(sa{sv})'), Gio.DBusCallFlags.NONE,
                30000, descriptors, None)
            doc_id, _ = reply.unpack()
            assert doc_id
            mount_reply = connection.call_sync(name, path, interface, 'GetMountPoint',
                None, GLib.VariantType.new('(ay)'), Gio.DBusCallFlags.NONE, 30000, None)
            mount = os.fsdecode(bytes(mount_reply.unpack()[0]).rstrip(b'\0'))
            destination = str(Path(mount) / doc_id / 'synthetic.pdf')
            command = ['flatpak', 'run', '--user', '--no-a11y-bus', '--nosocket=pcsc',
                       '--filesystem=' + str(tools) + ':ro',
                       '--env=LD_PRELOAD=' + str(tools / 'no-card-guard.so'),
                       '--command=' + str(tools / probe), APP_ID + '//test', destination]
            result = subprocess.run(command, text=True, capture_output=True, timeout=60)
            if expect_directory_error:
                assert result.returncode != 0 and 'cannot create directory' in result.stderr, result
            else:
                assert result.returncode == 0 and 'OUTPUT_STAGING_TESTS_OK' in result.stdout, result
                assert (Path(folder) / 'synthetic.pdf').read_text() == 'synthetic replacement'
                assert sorted(p.name for p in Path(folder).iterdir()) == ['synthetic.pdf']
            value = {'passed': True, 'realDocumentPortal': True,
                     'originalDirectoryErrorReproduced': expect_directory_error,
                     'newFileAndReplacementTestsPassed': not expect_directory_error,
                     'pcscSocketDisabled': True, 'pcscGuardPreloaded': True,
                     'appGuiLaunched': False, 'realCardTestsRun': False,
                     'browserConfigurationModified': False}
        finally:
            if doc_id:
                connection.call_sync(name, path, interface, 'Delete',
                    GLib.Variant('(s)', (doc_id,)), None,
                    Gio.DBusCallFlags.NONE, 30000, None)
    value['syntheticDocumentGrantRemoved'] = True
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(value, indent=2) + '\n')
    print(json.dumps(value, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tools', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--probe', default='output-staging-tests')
    parser.add_argument('--expect-directory-error', action='store_true')
    args = parser.parse_args()
    check(args.tools, args.report, args.probe, args.expect_directory_error)
