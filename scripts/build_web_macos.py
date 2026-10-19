#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build an isolated Universal CryptoTokenKit extension. Does not register it."""
import argparse,hashlib,json,plistlib,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--identity',required=True)
p.add_argument('--team-id',required=True,help='Apple signing team for the public-certificate-only App Group')
a=p.parse_args()
if not re.fullmatch(r"[A-Z0-9]{10}",a.team_id):raise SystemExit("Invalid signing team")
public_group=a.team_id+".it.giancarloezza.CIEID.FlutterPrototype.web-public"
if a.output.exists():raise SystemExit('Choose a new output directory')
runtime=a.runtime.resolve();manifest=json.loads((runtime/'backend-manifest.json').read_text())
for name in ['libcie_web.dylib','libcie-pkcs11.dylib']:
 if hashlib.sha256((runtime/name).read_bytes()).hexdigest()!=manifest['files'].get(name):raise SystemExit('Runtime mismatch: '+name)
extension=a.output/'CIEPrototypeToken.appex';contents=extension/'Contents'
executable=contents/'MacOS/CIEPrototypeToken';executable.parent.mkdir(parents=True)
frameworks=contents/'Frameworks';frameworks.mkdir()
for name in ['libcie_web.dylib','libcie-pkcs11.dylib']:shutil.copy2(runtime/name,frameworks/name)
bundle='it.giancarloezza.CIEID.FlutterPrototype.WebToken'
info=dict(CFBundleIdentifier=bundle,CFBundleExecutable='CIEPrototypeToken',CFBundleName='CIE ID · Accesso ai siti',CFBundleDisplayName='CIE ID · Accesso ai siti',CFBundlePackageType='XPC!',CFBundleVersion='12',CFBundleShortVersionString='0.1.11',CFBundleDevelopmentRegion='it',CFBundleLocalizations=['it'],LSMinimumSystemVersion='12.0',NSExtension=dict(NSExtensionPointIdentifier='com.apple.ctk-tokens',NSExtensionAttributes={'com.apple.ctk.class-id':bundle,'com.apple.ctk.driver-class':'CIEPrototypeTokenDriver','com.apple.ctk.token-type':'smartcard'}))
# Discover via the driver/ATR: automatic AID preselection skipped this CIE.
# Each token request opens one TKSmartCard session; IAS selects MF/IAS/CIE.
info['CIEWebPublicAppGroup']=public_group
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['xcrun','clang++','-std=c++17','-fobjc-arc','-fmodules','-arch','arm64','-arch','x86_64','-mmacosx-version-min=12.0','-I',str(ROOT/'native/include'),'-I',str(ROOT/'native/src'),str(ROOT/'native/platform/macos/web/CIEPrototypeToken.mm'),'-L',str(runtime),'-lcie_web','-framework','Foundation','-framework','CryptoTokenKit','-framework','Security','-Wl,-e,_NSExtensionMain','-Wl,-rpath,@executable_path/../Frameworks','-o',str(executable)],check=True)
for binary in frameworks.glob('*.dylib'):subprocess.run(['codesign','--force','--sign',a.identity,str(binary)],check=True)
entitlements=a.output/'WebToken.entitlements'
entitlements.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.smartcard':True,'com.apple.security.application-groups':[public_group]}))
subprocess.run(['codesign','--force','--sign',a.identity,'--entitlements',str(entitlements),str(extension)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(extension)],check=True)
shutil.copytree(runtime/'licenses',contents/'Resources/licenses')
# Resources must be sealed after copying the notices.
subprocess.run(['codesign','--force','--sign',a.identity,'--entitlements',str(entitlements),str(extension)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(extension)],check=True)
print(extension.resolve())
