#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Ubuntu 22.04 AppImage assembly. Does not install, configure browsers or use CIE."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from linux_package_common import ROOT, APP_ID, ARTIFACT_STEM, PREFIX, files, run, sha, source_revision, stage_payload, validate_bundle, validate_release_version
from package_linux_distribution import elf_files

# Keep the C library/loader, C++ runtime, graphics stack and PC/SC on the host.
# A bundled older libstdc++ would break newer host Mesa/LLVM drivers.
EXTERNAL = re.compile(r'^(?:ld-linux.*|lib(?:c|m|mvec|pthread|dl|rt|util|resolv|anl|nss_[^.]+)\.so(?:\..*)?|libstdc\+\+\.so.*|libgcc_s\.so.*|libpcsclite\.so.*|lib(?:GL|EGL|GLES|OpenGL|GLX|GLdispatch|drm|gbm|udev|vulkan|wayland)[^/]*\.so.*)$')
NSS_FILES={'libsoftokn3.so','libfreebl3.so','libfreeblpriv3.so','libnssckbi.so','libnssdbm3.so','libnss3.so','libnssutil3.so','libnspr4.so','libplc4.so','libplds4.so','libsmime3.so','modutil'}
WRAPPERS=('appimage_setup.py','appimage_firefox_setup.py','appimage_chrome_setup.py')
LOCK=ROOT/'linux/appimage/runtime.lock.json'

def maximum_versions(path):
    text=run('readelf','--version-info',path).stdout
    values={key:sorted(set(re.findall(r'\b'+key+r'_(\d+(?:\.\d+)+)',text)),key=lambda n:tuple(map(int,n.split('.'))))
            for key in ['GLIBC','GLIBCXX']}
    if 'GLIBC_ABI_' in text:raise ValueError('Unexpected newer glibc ABI feature: '+str(path))
    return {k:v[-1] if v else None for k,v in values.items()}

def check_abi(tree):
    results={}
    for p in elf_files(tree):
        version=maximum_versions(p)
        if version['GLIBC'] and tuple(map(int,version['GLIBC'].split('.')))>(2,35):
            raise ValueError('Requires glibc newer than Ubuntu 22.04: '+str(p)+' '+version['GLIBC'])
        if EXTERNAL.fullmatch(p.name):raise ValueError('Host library must not be bundled: '+str(p))
        results[p.relative_to(tree).as_posix()]=version
    return results

def stage(bundle,tree,native):
    stage_payload(bundle,tree/'layout',native,'appimage')
    layout=tree/'layout';app=tree/'usr/lib/firma-con-cie';app.parent.mkdir(parents=True)
    shutil.move(str(layout/PREFIX),app)
    shutil.move(str(layout/'usr/share'),tree/'usr/share');shutil.rmtree(layout)
    runtime=app/'cie_native';manifest=json.loads((runtime/'backend-manifest.json').read_text())
    for name in WRAPPERS:
        p=runtime/'browser_setup'/name;shutil.copy2(ROOT/'native/platform/linux/browser_setup'/name,p)
        manifest['files']['browser_setup/'+name]=sha(p)
    manifest['appimage_browser_persistent_module']=True
    (runtime/'backend-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (app/'tools').mkdir()
    for tool in ['python3','modutil']:
        script=app/'tools'/tool
        binary='python3.10' if tool=='python3' else 'modutil'
        flags=' -IB' if tool=='python3' else ''
        script.write_text('#!/bin/sh\nset -eu\nroot=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)\n'
            'unset GIO_MODULE_DIR GIO_EXTRA_MODULES GDK_PIXBUF_MODULE_FILE GTK_PATH GSETTINGS_SCHEMA_DIR FONTCONFIG_FILE FONTCONFIG_PATH LD_LIBRARY_PATH\n'
            'export XDG_DATA_DIRS="${CIE_APPIMAGE_HOST_DATA_DIRS:-/usr/local/share:/usr/share}"\n'
            'unset CIE_APPIMAGE_HOST_DATA_DIRS\n'+('export LD_LIBRARY_PATH="$root/usr/lib"\n' if tool=='modutil' else '')+'exec "$root/usr/bin/'+binary+'"'+flags+' "$@"\n')
        script.chmod(0o755)
    (tree/'usr/bin').mkdir(parents=True,exist_ok=True)
    sources={}
    def copy_tool(source,name):
        destination=tree/'usr/bin'/name;shutil.copy2(source,destination);sources[str(destination.relative_to(tree))]=str(source.resolve())
    copy_tool(Path('/usr/bin/python3.10'),'python3.10');copy_tool(Path('/usr/bin/modutil'),'modutil')
    # NSS loads these modules dynamically: DT_NEEDED alone is insufficient.
    for name in ['libsoftokn3.so','libfreebl3.so','libfreeblpriv3.so','libnssckbi.so','libnssdbm3.so']:
        source=Path('/usr/lib/x86_64-linux-gnu')/name
        if not source.is_file(): source=source.parent/'nss'/name
        if not source.is_file(): raise ValueError('Missing NSS runtime module: '+name)
        target=tree/'usr/lib'/name;shutil.copy2(source,target)
        sources[str(target.relative_to(tree))]=str(source.resolve())
        checksum=source.with_suffix('.chk')
        if checksum.is_file():
            target=tree/'usr/lib'/checksum.name;shutil.copy2(checksum,target)
            sources[str(target.relative_to(tree))]=str(checksum.resolve())
    query=Path('/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders')
    copy_tool(query,'gdk-pixbuf-query-loaders')
    shutil.copytree('/usr/lib/python3.10',tree/'usr/lib/python3.10',ignore=shutil.ignore_patterns('__pycache__','test','tests','site-packages','dist-packages'))
    for directory,relative,pattern in [('/usr/lib/x86_64-linux-gnu/gio/modules','usr/lib/gio/modules','*.so'),('/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders','usr/lib/gdk-pixbuf-2.0/2.10.0/loaders','*.so')]:
        dest=tree/relative;dest.mkdir(parents=True)
        for source in Path(directory).glob(pattern):
            target=dest/source.name;shutil.copy2(source,target);sources[str(target.relative_to(tree))]=str(source.resolve())
    fontconfig=tree/'usr/share/firma-con-cie/fontconfig';fontconfig.mkdir(parents=True)
    shutil.copytree('/etc/fonts/conf.d',fontconfig/'conf.d',symlinks=False)
    for name in ['fonts.conf','fonts.dtd']:
        source=Path('/etc/fonts/fonts.conf') if name=='fonts.conf' else Path('/usr/share/xml/fontconfig/fonts.dtd')
        shutil.copy2(source,fontconfig/name)
        sources[str((fontconfig/name).relative_to(tree))]=str(source)
    settings=(fontconfig/'fonts.conf').read_text().replace(
        '<cachedir prefix="xdg">fontconfig</cachedir>',
        '<cachedir prefix="xdg">firma-con-cie/appimage/fontconfig</cachedir>')
    (fontconfig/'fonts.conf').write_text(settings)
    schemas=tree/'usr/share/glib-2.0/schemas';schemas.mkdir(parents=True)
    for p in Path('/usr/share/glib-2.0/schemas').glob('*'):
        if p.is_file():shutil.copy2(p,schemas/p.name)
    run('glib-compile-schemas',schemas)
    # Ubuntu's Adwaita theme resources and MIME metadata for the bundled GTK.
    for source in ['/usr/share/themes/Adwaita','/usr/share/icons/Adwaita','/usr/share/mime']:
        p=Path(source)
        if p.exists():shutil.copytree(p,tree/str(p).lstrip('/'),symlinks=False,dirs_exist_ok=True)
    doc=tree/'usr/share/doc/cie-id-desktop';shutil.copy2(ROOT/'docs/LINUX_APPIMAGE.md',doc/'LINUX_APPIMAGE.md')
    icon=ROOT/'assets/branding/linux/hicolor/256x256/apps'/(APP_ID+'.png')
    shutil.copy2(icon,tree/'firma-con-cie.png');shutil.copy2(icon,tree/'.DirIcon')
    (tree/'firma-con-cie.desktop').write_text('[Desktop Entry]\nType=Application\nName=Firma con CIE\nExec=AppRun\nIcon=firma-con-cie\nCategories=Utility;Security;\nTerminal=false\nStartupWMClass='+APP_ID+'\n')
    run('desktop-file-validate',tree/'firma-con-cie.desktop')
    launcher='''#!/bin/sh
set -eu
umask 077
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export CIE_APPIMAGE=1
export CIE_APPIMAGE_HOST_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_DATA_DIRS="$root/usr/share:$CIE_APPIMAGE_HOST_DATA_DIRS"
export GIO_MODULE_DIR="$root/usr/lib/gio/modules"
unset GIO_EXTRA_MODULES
export GTK_PATH="$root/usr/lib/gtk-3.0"
export GTK_EXE_PREFIX="$root/usr"
export FONTCONFIG_PATH="$root/usr/share/firma-con-cie/fontconfig"
export FONTCONFIG_FILE="$FONTCONFIG_PATH/fonts.conf"
export GSETTINGS_SCHEMA_DIR="$root/usr/share/glib-2.0/schemas"
export GDK_PIXBUF_MODULEDIR="$root/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"
# Loader cache paths must follow this mount/extraction, which may change on every launch.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/firma-con-cie/appimage"
mkdir -p -- "$cache"
loader_cache=$(mktemp "$cache/loaders.XXXXXXXX")
"$root/usr/bin/gdk-pixbuf-query-loaders" > "$loader_cache"
export GDK_PIXBUF_MODULE_FILE="$loader_cache"
# No global LD_LIBRARY_PATH: external tools and host graphics retain their libraries.
set +e
"$root/usr/lib/firma-con-cie/Firma con CIE" "$@"
status=$?
rm -f -- "$loader_cache"
exit "$status"
'''
    (tree/'AppRun').write_text(launcher);(tree/'AppRun').chmod(0o755)
    return app,sources

def dependencies(tree,sources):
    initial=elf_files(tree)
    directories=sorted({str(p.parent) for p in initial})
    env=dict(os.environ,LD_LIBRARY_PATH=os.pathsep.join(directories))
    pending=list(initial);scanned=set();external=set()
    while pending:
        path=pending.pop()
        if path in scanned:continue
        scanned.add(path)
        result=subprocess.run(['ldd',str(path)],env=env,text=True,capture_output=True,check=True)
        if 'not found' in result.stdout+result.stderr:raise ValueError('Unresolved source library: '+str(path)+'\n'+result.stdout)
        for line in result.stdout.splitlines():
            match=re.match(r'\s*(\S+)\s+=>\s+(/\S+)\s+\(',line)
            if not match:continue
            soname,location=match.groups();source=Path(location).resolve()
            if EXTERNAL.fullmatch(soname):external.add(soname);continue
            if source.is_relative_to(tree):continue
            dest=tree/'usr/lib'/soname
            if dest.exists():
                if dest.read_bytes()!=source.read_bytes():raise ValueError('Conflicting private library: '+soname)
                continue
            shutil.copy2(source,dest);sources[str(dest.relative_to(tree))]=str(source);pending.append(dest)
    for path in elf_files(tree):
        # Preserve the vendor NSS/FIPS integrity checks. Its isolated tool
        # wrapper sets the private library path for that subprocess only.
        if path.name in NSS_FILES: continue
        old=run('patchelf','--print-rpath',path).stdout.strip().split(':')
        relative=os.path.relpath(tree/'usr/lib',path.parent)
        wanted=['$ORIGIN','$ORIGIN/'+relative]+[p for p in old if p.startswith('$ORIGIN')]
        if path.parent.name=='cie_native' and path.name in ['libcie_linux_pkcs11.so','libcie_web.so','libcie-pkcs11.so']:
            # The same three files must work after copying outside the AppDir.
            wanted=['$ORIGIN']
        run('patchelf','--set-rpath',':'.join(dict.fromkeys(wanted)),path)
    return sorted(external|{'libEGL.so.1','libGL.so.1','libGLESv2.so.2'})

def notices(tree,sources):
    licenses=tree/'usr/share/licenses/appimage-system-libraries';licenses.mkdir(parents=True)
    packages={}
    for name in sorted(set(sources.values())|{'/usr/bin/python3.10','/usr/bin/modutil'}):
        owners=[]
        aliases=[name,name.replace('/usr/lib/','/lib/',1)]
        for alias in dict.fromkeys(aliases):
            found=subprocess.run(['dpkg-query','-S',alias],capture_output=True,text=True)
            if found.returncode==0:
                owners=found.stdout.splitlines();break
        if not owners:raise ValueError('Unknown source package for library: '+name)
        for line in owners:
            package=line.split(': ',1)[0].split(':',1)[0]
            if package in packages:continue
            version=run('dpkg-query','-W','-f=${Version}',package).stdout
            notice=Path('/usr/share/doc')/package/'copyright'
            if not notice.is_file():raise ValueError('Missing dependency license: '+package)
            shutil.copy2(notice,licenses/(package+'-copyright'))
            packages[package]=version
    # Python stdlib is also governed by libpython3.10-stdlib's notices.
    for package in ['libpython3.10-stdlib','libpython3.10-minimal']:
        notice=Path('/usr/share/doc')/package/'copyright'
        shutil.copy2(notice,licenses/(package+'-copyright'))
        packages[package]=run('dpkg-query','-W','-f=${Version}',package).stdout
    (licenses/'packages.json').write_text(json.dumps(packages,indent=2)+'\n')
    return packages

def package(bundle,output,runtime,version):
    bundle,output,runtime=bundle.resolve(),output.resolve(),runtime.resolve()
    validate_release_version(version)
    if output.exists() or output.is_relative_to(bundle):raise ValueError('New output directory required')
    release=Path('/etc/os-release').read_text()
    if 'VERSION_ID="22.04"' not in release or 'ID=ubuntu' not in release:raise ValueError('Build AppImage inside Ubuntu 22.04')
    lock=json.loads(LOCK.read_text())
    if sha(runtime)!=lock['sha256']:raise ValueError('AppImage runtime checksum mismatch')
    native=validate_bundle(bundle);revision=source_revision()
    work=ROOT/'.build/appimage-packaging';work.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work) as temp:
        temp=Path(temp);tree=temp/'FirmaConCIE.AppDir'
        app,sources=stage(bundle,tree,native)
        external=dependencies(tree,sources);licenses=notices(tree,sources);abi=check_abi(tree)
        # Patched private native ELF files receive updated hashes for normal runtime verification.
        manifest=json.loads((app/'cie_native/backend-manifest.json').read_text())
        manifest['files']={n:sha(app/'cie_native'/n) for n in manifest['files']}
        (app/'cie_native/backend-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        data={p.relative_to(tree).as_posix():sha(p) for p in files(tree)}
        output.mkdir(parents=True);filesystem=temp/'payload.squashfs'
        run('mksquashfs',tree,filesystem,'-noappend','-comp','zstd','-Xcompression-level','15','-processors','2','-all-root',
            '-mkfs-time',str(revision['sourceDateEpoch']),'-all-time',str(revision['sourceDateEpoch']))
        target=output/(ARTIFACT_STEM+'-'+version+'-x86_64.AppImage')
        with target.open('wb') as out:
            for source in [runtime,filesystem]:
                with source.open('rb') as src:shutil.copyfileobj(src,out)
        target.chmod(0o755)
        offset=int(run(target,'--appimage-offset').stdout.strip());assert offset==runtime.stat().st_size
        result=dict(revision,format='appimage',version=version,architecture='x86_64',
            file=target.name,sha256=sha(target),bytes=target.stat().st_size,files=data,
            buildDistribution='Ubuntu 22.04',maximumGlibc='2.35',elfFilesChecked=len(abi),elfAbi=abi,
            externalLibraries=external,pcscFromHost=True,pcscDaemonBundled=False,
            cxxRuntimeFromHost=True,graphicsStackFromHost=True,pythonAndNssToolsBundled=True,
            persistentBrowserModule=True,browserFullPinRequired=True,appImageRuntime=lock,
            browserConfigurationModified=False,cardTestsRun=False,hostInstallationPerformed=False,
            appLaunched=False,dependencyPackages=licenses)
        (output/'package-manifest.json').write_text(json.dumps(result,indent=2)+'\n')
        (output/'SHA256SUMS').write_text(result['sha256']+'  '+target.name+'\n')
        shutil.copy2(ROOT/'docs/LINUX_APPIMAGE.md',output/'LEGGIMI.md')
        # Retain the exact AppDir for software checks only; it is not a user installation.
        shutil.move(str(tree),output/'AppDir')
        print(json.dumps({k:v for k,v in result.items() if k not in ['files','elfAbi','dependencyPackages']},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--bundle',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--version',required=True)
    a=p.parse_args();package(a.bundle,a.output,a.runtime,a.version)
