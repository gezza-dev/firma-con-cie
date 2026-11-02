#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Linux native HTTPS regression in a private root; synthetic trust is namespace-only."""
import argparse
import http.server
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading


def namespace_arguments(user_namespace=True):
    if user_namespace:
        return ['--unshare-user', '--uid', '0', '--gid', '0']
    if os.geteuid() != 0:
        raise RuntimeError('The mount-only namespace requires root inside the isolated container')
    return []


def trust_mount_arguments(ca, directory=None):
    # Fedora/Arch may make /etc/ssl/certs a symlink. Recent bubblewrap refuses
    # mounts onto a final symlink; mount the canonical directory in the child
    # namespace, without replacing links or touching the distribution's store.
    certificates = (directory or Path('/etc/ssl/certs')).resolve(strict=True)
    return ['--tmpfs', str(certificates), '--ro-bind', str(ca),
            str(certificates/'ca-certificates.crt')]


def check(client, report, user_namespace=True):
    if (not Path('/work/.cie-appimage-isolated-root').is_file()
            or Path('/run/pcscd/pcscd.comm').exists() or Path('/dev/bus/usb').exists()):
        raise RuntimeError('Use the private AppImage test root without card interfaces')
    bwrap = shutil.which('bwrap') or '/work/test-bwrap'
    with tempfile.TemporaryDirectory(prefix='cie-native-tls-') as temporary:
        root = Path(temporary)
        def openssl(*arguments):
            subprocess.run(['openssl', *map(str, arguments)], cwd=root, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for name in ['ca', 'foreign']:
            openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
                    '-subj', '/CN=Synthetic Linux TLS test', '-keyout', name+'.key', '-out', name+'.pem')
        openssl('req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost',
                '-keyout', 'server.key', '-out', 'server.csr')
        (root/'server.ext').write_text('subjectAltName=DNS:localhost\nbasicConstraints=critical,CA:FALSE\n'
                                     'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n')
        openssl('x509', '-req', '-in', 'server.csr', '-CA', 'ca.pem', '-CAkey', 'ca.key',
                '-CAcreateserial', '-days', '2', '-extfile', 'server.ext', '-out', 'server.pem')
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(root/'server.pem', root/'server.key')
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200); self.send_header('Content-Length', '4'); self.end_headers()
                self.wfile.write(b'TEST')
            def log_message(self, *_): pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        def request(url, ca='ca.pem', proxy=False):
            # The real system trust store stays read-only. Only the child mount
            # namespace sees the synthetic CA, with no other hashed roots.
            # Reuse the outer private /proc: nested namespaces cannot remount
            # it on every kernel. TLS does not need a separate proc filesystem.
            command = [bwrap, *namespace_arguments(user_namespace), '--unshare-pid',
                       '--unshare-ipc', '--unshare-uts', '--die-with-parent', '--ro-bind', '/', '/',
                       '--dev', '/dev', *trust_mount_arguments(root/ca), '--',
                       str(client), url, '0', '0']
            wire = ('CIE-NETWORK-1\n2\nlocalhost\n'+str(server.server_port)+'\n\n\n'
                    if proxy else 'CIE-NETWORK-1\n0\n\n0\n\n\n')
            response = subprocess.run(command, input=wire, text=True, capture_output=True, timeout=20)
            assert response.returncode == 0, response.stderr[-2000:]
            header, _, body = response.stdout.partition('\n')
            return json.loads(header), body
        try:
            url = 'https://localhost:'+str(server.server_port)+'/synthetic.crl'
            good, body = request(url)
            assert good['transportCode'] == 0 and body == 'TEST', good
            foreign, _ = request(url, ca='foreign.pem')
            assert foreign['transportCode'] == 60, foreign
            hostname, _ = request('https://127.0.0.1:'+str(server.server_port)+'/synthetic.crl')
            assert hostname['transportCode'] == 60, hostname
            proxy, body = request('http://example.invalid/synthetic.crl', proxy=True)
            assert proxy['transportCode'] == 0 and body == 'TEST', proxy
            bad_proxy, _ = request('http://example.invalid/synthetic.crl', ca='foreign.pem', proxy=True)
            assert bad_proxy['transportCode'] == 60, bad_proxy
        finally:
            server.shutdown(); server.server_close(); thread.join()
    result = dict(passed=True, nativeHttpsWithDestinationCa=True, unknownCaRejected=True,
                  hostnameMismatchRejected=True, httpsProxyWithDestinationCa=True,
                  untrustedHttpsProxyRejected=True, loopbackOnly=True,
                  systemTrustModified=False, realCardTestsRun=False)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--no-user-namespace', action='store_true',
                        help='Root-only CI container: retain mount isolation without nested UID mapping')
    args = parser.parse_args()
    check(args.client.resolve(), args.report.resolve(), not args.no_user_namespace)
