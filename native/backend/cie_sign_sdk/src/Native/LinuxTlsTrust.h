// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <filesystem>
#include <string>

namespace cie {
struct LinuxTlsTrust {
    std::string file;
    std::string directory;
};
// Use the destination's trust store, never paths autodetected in a cross-build
// sysroot. The optional root is only an internal seam for filesystem fixtures.
inline LinuxTlsTrust linuxTlsTrust(const std::filesystem::path& root = "/") {
    LinuxTlsTrust trust;
    std::error_code error;
    for (const char* name : {"etc/ssl/certs/ca-certificates.crt",
                             "etc/pki/tls/certs/ca-bundle.crt",
                             "etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
                             "etc/ssl/ca-bundle.pem"}) {
        auto path = root / name;
        if (std::filesystem::is_regular_file(path, error)) {
            trust.file = path.string();
            break;
        }
    }
    auto directory = root / "etc/ssl/certs";
    if (std::filesystem::is_directory(directory, error)) trust.directory = directory.string();
    return trust;
}
}
