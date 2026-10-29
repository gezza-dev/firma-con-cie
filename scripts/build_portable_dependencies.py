#!/usr/bin/env python3
"""Build checksum-pinned macOS/Linux/MinGW static dependencies in an isolated prefix."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tarfile
import urllib.request
from check_openssl_arm64 import validate_configuration as validate_openssl_arm64
from prepare_cryptopp_arm64 import prepare_windows_arm64 as prepare_cryptopp_arm64
from prepare_podofo_arm64 import prepare_windows_arm64 as prepare_podofo_arm64

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "native/backend/scripts/dependencies.lock.json").read_text())
ORDER = ["openssl", "cryptopp", "zlib", "bzip2", "libiconv", "expat",
         "libpng", "freetype", "fontconfig", "libxml2", "libcurl", "podofo"]
ARCHIVES = ["crypto", "ssl", "cryptopp", "z", "bz2", "iconv", "charset",
            "expat", "png16", "freetype", "fontconfig", "xml2", "curl", "podofo", "podofo_private", "podofo_3rdparty"]


def run(command, cwd, env, log):
    log.write("\n$ " + shlex.join([str(x) for x in command]) + "\n")
    log.flush()
    subprocess.run([str(x) for x in command], cwd=cwd, env=env,
                   stdout=log, stderr=subprocess.STDOUT, check=True)


def unpack(archive, destination):
    # Reject traversal and links escaping the source tree, including on Python 3.9.
    with tarfile.open(archive) as tar:
        root = destination.resolve()
        members = tar.getmembers()
        for member in members:
            target = (root / member.name).resolve()
            if not target.is_relative_to(root) or member.isdev():
                raise ValueError("Unsafe archive member: " + member.name)
            if member.issym() or member.islnk():
                base = target.parent if member.issym() else root
                if not (base / member.linkname).resolve().is_relative_to(root):
                    raise ValueError("Unsafe archive link: " + member.name)
        tar.extractall(root)
        return root / members[0].name.split("/")[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=["arm64", "aarch64", "x86_64"], default=platform.machine())
    parser.add_argument("--target", choices=["native", "windows-x64", "windows-arm64"], default="native")
    parser.add_argument("--deployment-target", default="12.0")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 6))
    parser.add_argument("--only", choices=ORDER, help="Build one dependency (prerequisites must exist)")
    parser.add_argument("--force", action="store_true", help="Rebuild selected dependencies")
    args = parser.parse_args()
    if platform.system() not in ["Darwin", "Linux"] or args.jobs < 1:
        parser.error("A macOS/Linux host and a positive job count are required")
    for tool in ["cmake", "make", "perl", "pkg-config", "meson", "ninja"] + (["xcrun", "lipo"] if platform.system() == "Darwin" else []):
        if not shutil.which(tool):
            parser.error("Missing build tool: " + tool)

    work = ROOT / ".build/dependencies"
    is_mac = platform.system() == "Darwin"
    is_windows = args.target in ("windows-x64", "windows-arm64")
    is_windows_arm = args.target == "windows-arm64"
    if is_windows_arm and (platform.system() != 'Linux' or args.arch not in ('arm64', 'aarch64')):
        parser.error('windows-arm64 requires a Linux host and --arch arm64')
    triplet = 'aarch64-w64-mingw32' if is_windows_arm else 'x86_64-w64-mingw32'
    target_name = args.target if is_windows else ("macos-" if is_mac else "linux-") + args.arch
    build_root = work / target_name
    prefix = build_root / "prefix"
    for path in [work / "downloads", build_root / "logs", prefix / "lib", prefix / "include"]:
        path.mkdir(parents=True, exist_ok=True)
    sdk = ""
    env = os.environ.copy()
    flags = "-O2 -fPIC"
    if is_mac:
        sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
        flags += shlex.join(["", "-arch", args.arch, "-isysroot", sdk, "-mmacosx-version-min=" + args.deployment_target])
        env.update(CC="clang", CXX="clang++", MACOSX_DEPLOYMENT_TARGET=args.deployment_target, SDKROOT=sdk)
    else:
        env.update(CC="gcc", CXX="g++")
    if is_windows:
        env.update(CC=triplet+('-clang' if is_windows_arm else '-gcc-posix'),
                   CXX=triplet+('-clang++' if is_windows_arm else '-g++-posix'),
                   AR=triplet+'-ar', RANLIB=triplet+'-ranlib', RC=triplet+'-windres')
        flags += " -D_WIN32_WINNT=" + ('0x0A00' if is_windows_arm else '0x0601')
        for tool in (env['CC'],env['CXX'],env['AR'],env['RANLIB'],env['RC']):
            if not shutil.which(tool):
                parser.error('Missing Windows cross compiler tool: '+tool)
    env.update(CFLAGS=flags, CXXFLAGS=flags + " -std=c++17", CPPFLAGS="-I" + shlex.quote(str(prefix / "include")),
               LDFLAGS=flags + (" -Wl,-adhoc_codesign" if is_mac else "") + " -L" + shlex.quote(str(prefix / "lib")),
               PKG_CONFIG_LIBDIR=os.pathsep.join([str(prefix / "lib/pkgconfig"), str(prefix / "share/pkgconfig")]), PKG_CONFIG_PATH="")
    if is_windows_arm:
        env['LDFLAGS'] += ' -static'
    toolchain = build_root / "mingw.cmake"
    if is_windows:
        toolchain.write_text("set(CMAKE_SYSTEM_NAME Windows)\nset(CMAKE_SYSTEM_PROCESSOR " + ('ARM64' if is_windows_arm else 'x86_64') + ")\n"
            "set(CMAKE_C_COMPILER " + env['CC'] + ")\nset(CMAKE_CXX_COMPILER " + env['CXX'] + ")\n"
            "set(CMAKE_RC_COMPILER " + env['RC'] + ")\n"
            + ('set(CMAKE_EXE_LINKER_FLAGS_INIT "-static")\nset(CMAKE_SHARED_LINKER_FLAGS_INIT "-static")\n' if is_windows_arm else '') +
            "set(CMAKE_FIND_ROOT_PATH " + (str(Path(shutil.which(env['CC'])).resolve().parents[1] / triplet) if is_windows_arm else '/usr/'+triplet) + ' "' + str(prefix) + "\")\n"
            "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)\nset(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)\n"
            "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)\nset(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)\n")
    recipe_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    compiler = subprocess.check_output([env["CC"], "--version"], text=True).splitlines()[0]
    sdk_version = platform.platform() if not is_mac else subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True).strip()

    def cmake(source, build, options, log):
        # Prevent optional libraries from silently linking to Homebrew dylibs.
        run(["cmake", "-S", source, "-B", build,
             "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DCMAKE_BUILD_TYPE=Release",
             *(["-DCMAKE_TOOLCHAIN_FILE=" + str(toolchain)] if is_windows else []),
             "-DCMAKE_OSX_ARCHITECTURES=" + args.arch,
             "-DCMAKE_OSX_DEPLOYMENT_TARGET=" + args.deployment_target,
             "-DCMAKE_OSX_SYSROOT=" + sdk, "-DCMAKE_INSTALL_PREFIX=" + str(prefix),
             "-DCMAKE_INSTALL_LIBDIR=lib", "-DCMAKE_PREFIX_PATH=" + str(prefix),
             "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local",
             "-DCMAKE_FIND_FRAMEWORK=LAST",
             "-DZLIB_USE_STATIC_LIBS=ON", "-DBUILD_SHARED_LIBS=OFF", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
             *options], ROOT, env, log)
        run(["cmake", "--build", build, "--parallel", args.jobs], ROOT, env, log)
        run(["cmake", "--install", build], ROOT, env, log)

    for name in [args.only] if args.only else ORDER:
        item = LOCK[name]
        stamp = build_root / (name + ".json")
        identity = dict(target=target_name, source=item, arch=args.arch, deployment_target=args.deployment_target,
                        recipe_hash=recipe_hash, compiler=compiler, sdk_version=sdk_version,
                        openssl_source=LOCK["openssl"] if name in ["libcurl", "podofo"] else None)
        if is_windows_arm and name == 'openssl':
            identity['arm64_config_sha256'] = hashlib.sha256((ROOT/'native/backend/scripts/windows-arm64-openssl.conf').read_bytes()).hexdigest()
        if is_windows_arm and name == 'cryptopp':
            identity['arm64_source_fix_sha256'] = hashlib.sha256((ROOT/'scripts/prepare_cryptopp_arm64.py').read_bytes()).hexdigest()
        if is_windows_arm and name == 'podofo':
            identity['arm64_source_fix_sha256'] = hashlib.sha256((ROOT/'scripts/prepare_podofo_arm64.py').read_bytes()).hexdigest()
            identity['arm64_charconv_probe_sha256'] = hashlib.sha256((ROOT/'native/tests/podofo_charconv_probe.cpp').read_bytes()).hexdigest()
        if not args.force and stamp.exists() and json.loads(stamp.read_text()) == identity:
            print("Already built: " + name, flush=True)
            continue
        archive = work / "downloads" / item["archive"]
        if not archive.exists():
            print("Downloading " + name, flush=True)
            temporary = archive.with_suffix(archive.suffix + ".part")
            with urllib.request.urlopen(item["url"], timeout=60) as response, temporary.open("wb") as out:
                shutil.copyfileobj(response, out)
            temporary.replace(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Checksum mismatch: " + str(archive))
        source_root = build_root / "sources" / name
        shutil.rmtree(source_root, ignore_errors=True)
        source_root.mkdir(parents=True)
        source = unpack(archive, source_root)
        build = build_root / "build" / name
        shutil.rmtree(build, ignore_errors=True)
        build.mkdir(parents=True)
        log_path = build_root / "logs" / (name + ".log")
        print("Building " + name + " " + item["version"] + " for " + args.arch + " (" + str(log_path) + ")", flush=True)
        try:
            with log_path.open("w") as log:
                if name == "openssl":
                    if is_windows_arm:
                        shutil.copy2(ROOT/'native/backend/scripts/windows-arm64-openssl.conf', source/'Configurations/99-cie-windows-arm64.conf')
                    target = "mingw-arm64-cie" if is_windows_arm else "mingw64" if is_windows else ("darwin64-" + ("arm64" if args.arch == "arm64" else "x86_64") + "-cc" if is_mac else "linux-aarch64" if args.arch in ["arm64", "aarch64"] else "linux-x86_64")
                    run(["perl", source / "Configure", target, "no-shared", "no-module", "no-autoload-config", "no-tests", "no-asm",
                         "--libdir=lib", "--prefix=" + str(prefix), "--openssldir=" + str(prefix / "ssl")], build, env, log)
                    if is_windows_arm:
                        validate_openssl_arm64(build)
                    run(["make", "-j" + str(args.jobs)], build, env, log)
                    run(["make", "install_sw"], build, env, log)
                elif name == "cryptopp":
                    if is_windows_arm:
                        prepare_cryptopp_arm64(source)
                    run(["make", "-j" + str(args.jobs), "libcryptopp.a", "CXX=" + env["CXX"],
                         "IS_ARM32=0", *(["IS_MINGW=1", "AR=" + env["AR"], "RANLIB=" + env["RANLIB"]] if is_windows else []), "CXXFLAGS=" + flags + " -std=c++17 -DCRYPTOPP_DISABLE_ASM"], source, env, log)
                    shutil.copy2(source / "libcryptopp.a", prefix / "lib")
                    headers = prefix / "include/cryptopp"
                    headers.mkdir(exist_ok=True)
                    for header in source.glob("*.h"):
                        shutil.copy2(header, headers)
                elif name == "bzip2":
                    run(["make", "-j" + str(args.jobs), "libbz2.a", "CC=" + env["CC"], "CFLAGS=" + flags, *(["AR=" + env["AR"], "RANLIB=" + env["RANLIB"]] if is_windows else [])], source, env, log)
                    shutil.copy2(source / "libbz2.a", prefix / "lib")
                    shutil.copy2(source / "bzlib.h", prefix / "include")
                elif name == "libiconv":
                    build_triplet = subprocess.check_output(
                        ["sh", source / "build-aux/config.guess"], text=True).strip()
                    run([source / "configure", "--prefix=" + str(prefix),
                         "--build=" + build_triplet,
                         "--host=" + (triplet if is_windows else ("aarch64" if args.arch in ["arm64", "aarch64"] else "x86_64") + ("-apple-darwin" if is_mac else "-linux-gnu")),
                         "--enable-static", "--disable-shared", "--disable-nls"], build, env, log)
                    run(["make", "-j" + str(args.jobs)], build, env, log)
                    run(["make", "install"], build, env, log)
                elif name == "fontconfig" and not is_mac:
                    cross = build_root / "fontconfig-cross.ini"
                    if is_windows:
                        cross.write_text("[binaries]\nc = " + repr(env["CC"]) + "\ncpp = " + repr(env["CXX"]) +
                            "\nar = '" + env['AR'] + "'\nstrip = '" + triplet + "-strip'\npkg-config = 'pkg-config'\n"
                            "[host_machine]\nsystem = 'windows'\ncpu_family = '" + ('aarch64' if is_windows_arm else 'x86_64') + "'\ncpu = '" + ('aarch64' if is_windows_arm else 'x86_64') + "'\nendian = 'little'\n")
                    run(["meson", "setup", build, source, *(["--cross-file", cross] if is_windows else []), "--prefix=" + str(prefix), "--libdir=lib", "--buildtype=release", "-Ddefault_library=static", "-Ddoc=disabled", "-Dnls=disabled", "-Dtests=disabled", "-Dtools=disabled", "-Dcache-build=disabled", "-Dtests-external-fonts=disabled", "-Dxml-backend=expat"], ROOT, env, log)
                    run(["meson", "compile", "-C", build, "-j", args.jobs], ROOT, env, log)
                    run(["meson", "install", "-C", build], ROOT, env, log)
                elif name == "fontconfig":
                    cross = build_root / "fontconfig-cross.ini"
                    family = "aarch64" if args.arch == "arm64" else "x86_64"
                    cross.write_text("[binaries]\nc = " + repr(env["CC"]) + "\ncpp = " + repr(env["CXX"]) +
                        "\npkg-config = 'pkg-config'\n[host_machine]\nsystem = 'darwin'\ncpu_family = '" + family +
                        "'\ncpu = '" + family + "'\nendian = 'little'\n[properties]\nneeds_exe_wrapper = false\n")
                    run(["meson", "setup", build, source, "--cross-file", cross,
                         "--prefix=" + str(prefix), "--libdir=lib", "--buildtype=release",
                         "-Ddefault_library=static", "-Ddoc=disabled", "-Dnls=disabled", "-Dtests=disabled",
                         "-Dtools=disabled", "-Dcache-build=disabled", "-Dtests-external-fonts=disabled",
                         "-Dxml-backend=expat", "-Dadditional-fonts-dirs=/System/Library/Fonts,/Library/Fonts"], ROOT, env, log)
                    run(["meson", "compile", "-C", build, "-j", args.jobs], ROOT, env, log)
                    run(["meson", "install", "-C", build], ROOT, env, log)
                elif name == "zlib":
                    cmake(source, build, ["-DZLIB_BUILD_EXAMPLES=OFF"], log)
                    if is_windows:
                        shutil.copy2(prefix / "lib/libzs.a", prefix / "lib/libz.a")
                    # zlib's older CMake builds both variants even with BUILD_SHARED_LIBS=OFF.
                    for dynamic in (prefix / "lib").glob("libz*.dylib"):
                        dynamic.unlink()
                elif name == "expat":
                    cmake(source / "expat" if (source / "expat/CMakeLists.txt").exists() else source, build, ["-DEXPAT_SHARED_LIBS=OFF", "-DEXPAT_BUILD_TESTS=OFF",
                          "-DEXPAT_BUILD_EXAMPLES=OFF", "-DEXPAT_BUILD_TOOLS=OFF", "-DEXPAT_BUILD_DOCS=OFF"], log)
                elif name == "libpng":
                    shutil.rmtree(prefix / "lib/png.framework", ignore_errors=True)
                    cmake(source, build, ["-DPNG_SHARED=OFF", "-DPNG_FRAMEWORK=OFF", "-DPNG_TESTS=OFF", "-DPNG_TOOLS=OFF"], log)
                elif name == "freetype":
                    cmake(source, build, ["-DFT_DISABLE_HARFBUZZ=ON", "-DFT_DISABLE_BROTLI=ON"], log)
                elif name == "libxml2":
                    cmake(source, build, ["-DLIBXML2_WITH_PYTHON=OFF", "-DLIBXML2_WITH_PROGRAMS=OFF",
                          "-DLIBXML2_WITH_TESTS=OFF", "-DLIBXML2_WITH_LZMA=OFF", "-DLIBXML2_WITH_ICU=OFF"], log)
                elif name == "libcurl":
                    # glibc 2.43 adds fortified memset_explicit. Retain curl's
                    # non-optimizable explicit_bzero fallback on Linux so the
                    # module also loads in Firefox Snap's core24 (glibc 2.39).
                    cmake(source, build, (["-DHAVE_MEMSET_EXPLICIT:BOOL=OFF"] if not is_mac and not is_windows else []) + ["-DBUILD_CURL_EXE=OFF", "-DBUILD_TESTING=OFF",
                          "-DCURL_USE_OPENSSL=ON", "-DUSE_APPLE_SECTRUST=" + ("ON" if is_mac else "OFF"), "-DOPENSSL_ROOT_DIR=" + str(prefix),
                          "-DCURL_USE_LIBPSL=OFF", "-DCURL_USE_LIBSSH2=OFF", "-DUSE_NGHTTP2=OFF",
                          "-DCURL_BROTLI=OFF", "-DCURL_ZSTD=OFF", "-DUSE_LIBIDN2=OFF",
                          "-DCURL_USE_GSSAPI=OFF", "-DCURL_USE_SECTRANSP=OFF"], log)
                elif name == "podofo":
                    if is_windows_arm:
                        prepare_podofo_arm64(source)
                        run([env['CXX'], '-std=c++17', '-static',
                             '-I'+str(source/'src/podofo/private'),
                             ROOT/'native/tests/podofo_charconv_probe.cpp',
                             '-o', build/'podofo_charconv_probe.exe'], ROOT, env, log)
                    cmake(source, build, (["-DCMAKE_CXX_FLAGS=" + env["CXXFLAGS"] + " -DLIBXML_STATIC"] if is_windows else []) + ["-DPODOFO_BUILD_STATIC=ON", "-DPODOFO_BUILD_LIB_ONLY=ON",
                          "-DPODOFO_WITH_AFDKO=OFF", "-DCMAKE_CXX_STANDARD=17",
                          "-DCMAKE_DISABLE_FIND_PACKAGE_JPEG=ON", "-DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON",
                          "-DCMAKE_DISABLE_FIND_PACKAGE_LCMS2=ON",
                          "-DFREETYPE_INCLUDE_DIR_FT2BUILD=" + str(prefix / "include/freetype2"),
                          "-DFREETYPE_INCLUDE_DIR_FTHEADER=" + str(prefix / "include/freetype2"),
                          "-DFREETYPE_LIBRARY_RELEASE=" + str(prefix / "lib/libfreetype.a")], log)

        except subprocess.CalledProcessError:
            print(log_path.read_text()[-6000:], flush=True)
            raise SystemExit("Build failed: " + name + "; see " + str(log_path))
        stamp.write_text(json.dumps(identity, indent=2) + "\n")

    if not args.only:
        for name in ARCHIVES:
            path = prefix / "lib" / ("lib" + name + ".a")
            if not path.is_file():
                raise ValueError("Missing static dependency: " + str(path))
            arches = subprocess.check_output(["lipo", "-archs", path], text=True).split() if is_mac else [args.arch]
            if arches != [args.arch]:
                raise ValueError("Unexpected architecture: " + str(path) + ": " + str(arches))
        (prefix / "cie-dependencies.json").write_text(json.dumps(dict(
            arch=args.arch, deployment_target=args.deployment_target, sources=LOCK), indent=2) + "\n")
        print("Verified static dependencies: " + str(prefix), flush=True)


if __name__ == "__main__":
    main()
