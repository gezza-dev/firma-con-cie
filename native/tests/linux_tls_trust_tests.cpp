// SPDX-License-Identifier: BSD-3-Clause
#include "LinuxTlsTrust.h"
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace fs = std::filesystem;
void require(bool value) { if (!value) throw std::runtime_error("Linux TLS trust fixture failed"); }
int main() {
    char pattern[] = "/tmp/cie-linux-tls-trust-XXXXXX";
    const char* temporary = mkdtemp(pattern);
    if (!temporary) return 1;
    fs::path root(temporary);
    try {
        auto trust = cie::linuxTlsTrust(root);
        require(trust.file.empty() && trust.directory.empty());
        for (auto name : {"etc/ssl/certs/ca-certificates.crt", "etc/pki/tls/certs/ca-bundle.crt",
                          "etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", "etc/ssl/ca-bundle.pem"}) {
            fs::remove_all(root); auto path = root / name;
            fs::create_directories(path.parent_path()); std::ofstream(path) << "synthetic CA fixture";
            require(cie::linuxTlsTrust(root).file == path.string());
        }
        fs::remove_all(root); fs::create_directories(root / "etc/ssl/certs");
        trust = cie::linuxTlsTrust(root);
        require(trust.file.empty() && trust.directory == (root / "etc/ssl/certs").string());
        auto bundle = root / "etc/ssl/certs/ca-certificates.crt";
        fs::create_directory(bundle); require(cie::linuxTlsTrust(root).file.empty());
        fs::remove(bundle); std::ofstream(root / "bundle.pem") << "synthetic CA fixture";
        fs::create_symlink(root / "bundle.pem", bundle);
        require(cie::linuxTlsTrust(root).file == bundle.string());
        fs::remove_all(root);
        std::cout << "PASS destination CA bundles, hashed directory, missing store and system symlink\n";
        return 0;
    } catch (const std::exception& error) {
        fs::remove_all(root); std::cerr << error.what() << '\n'; return 1;
    }
}
