#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Extracted-package D-Bus activation, only inside a private build root."""
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
from gi.repository import Gio,GLib
BUS='it.giancarloezza.FirmaConCIE.BrowserHelper1';OBJECT='/it/giancarloezza/FirmaConCIE/BrowserHelper1'
home=Path('/work/browser-helper-user')
assert Path('/work/browser-helper-test-root').read_text()=='synthetic-only\n'
assert pwd.getpwuid(os.getuid()).pw_dir==str(home)
assert not Path('/run/pcscd/pcscd.comm').exists()
os.umask(0o077);home.mkdir(mode=0o700,exist_ok=True)
roots=[home/'.mozilla/firefox',home/'snap/firefox/common/.mozilla/firefox']
profiles=[]
foreign=b'library=\nname=NSS Internal PKCS #11 Module\nNSS=Flags=internal,critical\n\n'
for root in roots:
    p=root/'synthetic';p.mkdir(parents=True)
    (root/'profiles.ini').write_text('[Profile0]\nName=Synthetic activation test\nIsRelative=1\nPath=synthetic\n')
    profiles.append(p)
db=home/'.local/share/pki/nssdb';db.mkdir(parents=True);profiles.append(db)
for p in profiles:
    (p/'pkcs11.txt').write_bytes(foreign)
    (p/'cert9.db').write_bytes(b'synthetic certificate database, preserve')
    (p/'key4.db').write_bytes(b'synthetic key database, preserve')
subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-subj','/CN=Synthetic activation test',
    '-keyout',str(home/'synthetic.key'),'-outform','DER','-out',str(home/'synthetic.der'),'-days','1'],
    check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
certificates={'SYNTHETIC':(home/'synthetic.der').read_bytes().hex()}
connection=Gio.bus_get_sync(Gio.BusType.SESSION,None)
def request(op,**kwargs):
    raw=json.dumps(dict(protocol=1,op=op,certificates=certificates,**kwargs))
    reply=connection.call_sync(BUS,OBJECT,BUS,'Request',GLib.Variant('(s)',(raw,)),
        GLib.VariantType.new('(s)'),Gio.DBusCallFlags.NONE,30000,None)
    result=json.loads(reply.unpack()[0]);assert result['ok'],result
    return result
assert request('status')['fullPinRequired']
firefox=request('firefox.inspect');assert len(firefox['profiles'])==2,firefox
for item in firefox['profiles']:
    plan=request('firefox.plan',profile=item['id']);assert not plan['alreadyConfigured']
    assert request('firefox.apply',profile=item['id'],fingerprint=plan['fingerprint'])['publicDataPrepared']
assert all(p['state']=='configured' for p in request('firefox.inspect')['profiles'])
assert request('chrome.inspect')['state']=='needs_setup'
plan=request('chrome.plan');request('chrome.apply',fingerprint=plan['fingerprint'])
assert request('chrome.inspect')['state']=='configured'
for p in profiles:
    assert (p/'cert9.db').read_bytes()==b'synthetic certificate database, preserve'
    assert (p/'key4.db').read_bytes()==b'synthetic key database, preserve'
    assert (p/'pkcs11.txt').read_bytes().startswith(foreign)
assert not list(home.rglob('*.card'))
assert len(list(home.rglob('*.web')))==1
assert len(list((home/'snap/firefox/common/cie-id-web-v1').glob('*.der')))==1
print(json.dumps(dict(passed=True,sessionActivationVerified=True,extractedPackageOnly=True,
    targets=['Firefox','Firefox Snap','Chrome'],publicCertificatesOnly=True,
    productionUtilityUsed=True,fullPinRequired=True,realCardTestsRun=False,
    realBrowserConfigurationModified=False,hostInstallationPerformed=False)))
