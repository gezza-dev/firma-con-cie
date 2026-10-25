#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Separate host companion test packages. No install, browser or card operation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from linux_package_common import ROOT, files, run, sha, source_revision
from package_linux_distribution import elf_files, payload_tar

PACKAGE='firma-con-cie-browser-helper'
PREFIX=Path('opt')/PACKAGE
BUS='it.giancarloezza.FirmaConCIE.BrowserHelper1'
LIBRARIES=('libcie_linux_pkcs11.so','libcie_web.so','libcie-pkcs11.so')
SCRIPTS=('firefox_setup.py','chrome_setup.py','flatpak_helper.py','flatpak_service.py')

def stage(runtime, publisher, output):
    manifest=json.loads((runtime/'backend-manifest.json').read_text())
    if manifest['system']!='linux' or not all(manifest.get(k) for k in
            ['linux_web_full_pin_only','linux_firefox_pkcs11','linux_firefox_snap_core24_abi_verified']):
        raise ValueError('Verified Linux full-PIN runtime required')
    app=output/PREFIX;app.mkdir(parents=True)
    names=[*LIBRARIES,'browser_setup/libcie_browser_setup_guard.so',
           'browser_setup/firefox_setup.py','browser_setup/chrome_setup.py']
    for name in names:
        src=runtime/name
        if src.is_symlink() or sha(src)!=manifest['files'][name]:
            raise ValueError('Runtime checksum mismatch: '+name)
        if name.endswith('.py') and src.read_bytes()!=(ROOT/'native/platform/linux'/name).read_bytes():
            raise ValueError('Use unchanged native browser setup scripts')
        dest=app/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
    for name in ['flatpak_helper.py','flatpak_service.py']:
        shutil.copy2(ROOT/'native/platform/linux/browser_setup'/name,app/'browser_setup'/name)
    if publisher.is_symlink() or publisher.read_bytes()[:4]!=b'\x7fELF':
        raise ValueError('Compiled public certificate utility required')
    # Production publishers must never include the synthetic cache override.
    if b'CIE_PAIRING_TEST_CACHE' in publisher.read_bytes():
        raise ValueError('Test-only public certificate utility refused')
    shutil.copy2(publisher,app/'cie_browser_public_certificate')
    shutil.copytree(runtime/'licenses',app/'licenses')
    packaged={k:manifest[k] for k in ['system','linux_web_full_pin_only','linux_firefox_pkcs11','linux_firefox_snap_core24_abi_verified']}
    packaged.update(protocol=1,publicCertificatesOnly=True,files={p.relative_to(app).as_posix():sha(p) for p in files(app)})
    (app/'backend-manifest.json').write_text(json.dumps(packaged,indent=2)+'\n')
    services=output/'usr/share/dbus-1/services';services.mkdir(parents=True)
    (services/(BUS+'.service')).write_text('[D-BUS Service]\nName='+BUS+'\nExec=/usr/bin/python3 -I /'+str(PREFIX)+'/browser_setup/flatpak_service.py\n')
    doc=output/'usr/share/doc'/PACKAGE;doc.mkdir(parents=True)
    for src in [ROOT/'LICENSE',ROOT/'NOTICE.md',ROOT/'docs/LINUX_FLATPAK.md',ROOT/'docs/BUILDING.md']:
        shutil.copy2(src,doc/src.name)
    lic=output/'usr/share/licenses'/PACKAGE;lic.mkdir(parents=True);shutil.copy2(ROOT/'LICENSE',lic/'LICENSE')
    for path in output.rglob('*'):
        path.chmod(0o755 if path.is_dir() or path.suffix=='.so' or path.name=='cie_browser_public_certificate' else 0o644)
    return packaged

def system_libraries(stage, elfs):
    system=set();env=dict(os.environ,LD_LIBRARY_PATH=os.pathsep.join(str(p.parent) for p in elfs))
    for path in elfs:
        result=subprocess.run(['ldd',str(path)],check=True,text=True,capture_output=True,env=env)
        if 'not found' in result.stdout+result.stderr: raise ValueError('Unresolved target ABI: '+str(path))
        for line in result.stdout.splitlines():
            match=re.search(r'(?:=>\s+|^\s*)(/\S+)\s+\(',line)
            if match:
                library=Path(match[1]).resolve()
                if not library.is_relative_to(stage):system.add(str(library))
    return system

def deb(stage,elfs,temp,output,version):
    (temp/'debian').mkdir();(temp/'debian/control').write_text(f'Source: {PACKAGE}\n\nPackage: {PACKAGE}\nArchitecture: any\nDescription: Test host companion\n')
    scan=run('dpkg-shlibdeps','-O','-S'+str(stage),'-l'+str(stage/PREFIX),
        *('-e'+str(p) for p in elfs),cwd=temp)
    deps=next(s.split('=',1)[1] for s in scan.stdout.splitlines() if s.startswith('shlibs:Depends='))
    deps+=', python3 (>= 3.9), python3-gi, libnss3-tools, libpcsclite1, pcscd'
    control=stage/'DEBIAN';control.mkdir()
    (control/'control').write_text(f'Package: {PACKAGE}\nVersion: {version}\nArchitecture: amd64\n'
        'Maintainer: Gian Carlo Ezza <61827135+gezza-dev@users.noreply.github.com>\n'
        f'Depends: {deps}\nRecommends: libccid\nSection: utils\nPriority: optional\n'
        f'Installed-Size: {sum((p.stat().st_size+1023)//1024 for p in files(stage))}\n'
        'Description: Website access companion for Firma con CIE Flatpak - test\n'
        ' Per-user session D-Bus service, activated only by explicit application requests.\n'
        ' Full PIN required in the browser. Installation never changes browser settings.\n')
    (control/'md5sums').write_text(''.join(hashlib.md5(p.read_bytes()).hexdigest()+'  '+p.relative_to(stage).as_posix()+'\n' for p in files(stage) if not p.is_relative_to(control)))
    target=output/f'{PACKAGE}_{version}_amd64.deb'
    run('dpkg-deb','--root-owner-group','-Zxz','-z6','--threads-max=2','--build',stage,target)
    (output/'dependency-scan.log').write_text(scan.stdout+scan.stderr)
    return target,version,deps.split(', ')

def rpm(stage,elfs,temp,output,version,epoch):
    base,suffix=version.split('~test');release='0.test'+suffix
    config=run('rpm','-E','%{_rpmconfigdir}').stdout.strip()
    raw=run(Path(config)/'rpmdeps','--requires',*elfs).stdout.splitlines()
    deps=sorted({r for r in raw if r.split('(',1)[0] not in {p.name for p in elfs}}|{'python3 >= 3.9','python3-gobject-base','nss-tools','pcsc-lite'})
    top=temp/'rpm'
    for name in ['SOURCES','SPECS','BUILD','BUILDROOT','RPMS','SRPMS']: (top/name).mkdir(parents=True)
    payload_tar(stage,top/'SOURCES/payload.tar.gz',epoch)
    entries=[]
    for p in sorted(stage.rglob('*')):
        name='/'+p.relative_to(stage).as_posix()
        if p.is_file():entries.append('"'+name+'"')
        elif p.is_relative_to(stage/PREFIX) or p.is_relative_to(stage/'usr/share/doc'/PACKAGE) or p.is_relative_to(stage/'usr/share/licenses'/PACKAGE):entries.append('%dir "'+name+'"')
    (top/'SOURCES/files.list').write_text('\n'.join(entries)+'\n')
    spec=f'''%global debug_package %{{nil}}
%global __debug_install_post %{{nil}}
%global __os_install_post %{{nil}}
%global _build_id_links none
Name: {PACKAGE}
Version: {base}
Release: {release}
Summary: Website access companion for Firma con CIE Flatpak - test
License: LicenseRef-FirmaConCIE-Bundled
BuildArch: x86_64
Source0: payload.tar.gz
Source1: files.list
AutoReqProv: no
Requires: {', '.join(deps)}
Recommends: pcsc-lite-ccid
%description
Session D-Bus companion for explicit browser setup with the full PIN.
Installation does not configure browsers or start the service.
%prep
%setup -q -c -T
tar -xzf %{{SOURCE0}}
%install
mkdir -p "%{{buildroot}}"
cp -a opt usr "%{{buildroot}}/"
%files -f %{{SOURCE1}}
'''
    recipe=top/'SPECS'/f'{PACKAGE}.spec';recipe.write_text(spec)
    run('rpmbuild','-bb','--define','_topdir '+str(top),'--define','_smp_mflags -j2','--define','_smp_build_ncpus 2','--define','_binary_payload w6.xzdio',recipe)
    built,=(top/'RPMS/x86_64').glob('*.rpm');target=output/built.name;shutil.copy2(built,target)
    shutil.copy2(recipe,output/recipe.name)
    return target,base+'-'+release,deps

def arch(stage,system,temp,output,version,epoch):
    depends=sorted({run('pacman','-Qoq',p).stdout.strip() for p in system}|{'python','python-gobject','nss','pcsclite'})
    inputs=temp/'arch';inputs.mkdir();payload_tar(stage,inputs/'payload.tar.gz',epoch)
    converted=version.replace('~','_')
    recipe=f'''# Local test companion. No install hooks or browser changes.
pkgname={PACKAGE}
pkgver={converted}
pkgrel=1
pkgdesc='Website access companion for Firma con CIE Flatpak - test'
arch=('x86_64')
url='https://github.com/gezza-dev/cie-id-desktop'
license=('LicenseRef-FirmaConCIE-Bundled')
depends=({' '.join(repr(d) for d in depends)})
optdepends=('ccid: CCID smart card reader driver')
options=('!strip' '!debug' '!buildflags')
source=('payload.tar.gz')
sha256sums=('{sha(inputs/'payload.tar.gz')}')
package() {{
 cp -a --no-preserve=ownership "$srcdir/opt" "$srcdir/usr" "$pkgdir/"
}}
'''
    (inputs/'PKGBUILD').write_text(recipe);(inputs/'makepkg.conf').write_text('source /etc/makepkg.conf\nCOMPRESSZST=(zstd -c -T2 -10 -)\n')
    run('makepkg','--config',inputs/'makepkg.conf','--cleanbuild','--noconfirm',cwd=inputs)
    built,=inputs.glob('*.pkg.tar.zst');target=output/built.name;shutil.copy2(built,target);shutil.copy2(inputs/'PKGBUILD',output/'PKGBUILD')
    return target,converted+'-1',depends

def package(runtime,publisher,output,kind,version):
    if not re.fullmatch(r'\d[\d.]*~test\d{8}\.\d+',version): raise ValueError('Explicit ~testYYYYMMDD.N version required')
    output=output.resolve()
    if output.exists() or output.is_relative_to(runtime.resolve()): raise ValueError('New output directory required')
    revision=source_revision();work=ROOT/'.build/browser-helper-packaging';work.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work) as directory:
        temp=Path(directory);tree=temp/'stage';stage(runtime.resolve(),publisher.resolve(),tree)
        elfs=elf_files(tree);system=system_libraries(tree,elfs)
        payload={p.relative_to(tree).as_posix():sha(p) for p in files(tree)}
        output.mkdir(parents=True)
        if kind=='deb':target,ver,deps=deb(tree,elfs,temp,output,version)
        elif kind=='rpm':target,ver,deps=rpm(tree,elfs,temp,output,version,revision['sourceDateEpoch'])
        else:target,ver,deps=arch(tree,system,temp,output,version,revision['sourceDateEpoch'])
        metadata=dict(revision,package=PACKAGE,format=kind,version=ver,architecture='x86_64',file=target.name,
            sha256=sha(target),bytes=target.stat().st_size,applicationPrefix='/'+str(PREFIX),
            protocol=1,depends=deps,elfFilesChecked=len(elfs),fullPinRequired=True,publicCertificatesOnly=True,
            browserConfigurationModified=False,snapPermissionsModified=False,cardTestsRun=False,
            hostInstallationPerformed=False,serviceStarted=False,files=payload)
        (output/'package-manifest.json').write_text(json.dumps(metadata,indent=2)+'\n')
        (output/'SHA256SUMS').write_text(metadata['sha256']+'  '+target.name+'\n')
        shutil.copy2(ROOT/'docs/LINUX_FLATPAK.md',output/'LEGGIMI.md')
        print(json.dumps({k:v for k,v in metadata.items() if k!='files'},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime',type=Path,required=True);p.add_argument('--publisher',type=Path,required=True)
    p.add_argument('--format',choices=['deb','rpm','arch'],required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--version',required=True)
    a=p.parse_args();package(a.runtime,a.publisher,a.output,a.format,a.version)
