// SPDX-License-Identifier: BSD-3-Clause
#include "snap_public_store.h"
#include "paired_store.h"
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/x509.h>
#include <cerrno>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <pwd.h>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

namespace cie_linux_snap {
namespace {
namespace fs = std::filesystem;
constexpr const char* leaf = "cie-id-web-v1";
struct Fd {
    int value = -1;
    ~Fd() { if (value >= 0) close(value); }
    Fd() = default;
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};
[[noreturn]] void fail() { throw std::runtime_error("web_snap_public_store_unavailable"); }
fs::path common() {
#ifdef CIE_PAIRING_TEST_SERVICE
    const char* base = std::getenv("CIE_PAIRING_TEST_CACHE");
    if (!base || !fs::path(base).is_absolute()) fail();
    return fs::canonical(base) / "snap/firefox/common";
#else
    struct passwd user{}, *found = nullptr;
    char buffer[32768];
    if (getpwuid_r(getuid(), &user, buffer, sizeof(buffer), &found) ||
        !found || !user.pw_dir) fail();
    return fs::path(user.pw_dir) / "snap/firefox/common";
#endif
}
void private_entry(int fd, bool directory) {
    struct stat st{};
    if (fstat(fd, &st) || st.st_uid != getuid() || (st.st_mode & 0077) ||
        (directory ? !S_ISDIR(st.st_mode) : (!S_ISREG(st.st_mode) || st.st_nlink != 1))) fail();
}
// Walk existing parents without symlinks. Never create a Firefox Snap data
// directory: publishing is optional when that installation is absent.
int directory(bool create) {
    Fd parent;
    parent.value = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (parent.value < 0) fail();
    const auto path = common();
    for (const auto& component : path.relative_path()) {
        if (component == "." || component == "..") fail();
        int next = openat(parent.value, component.c_str(),
                          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) { if (errno == ENOENT) return -1; fail(); }
        close(parent.value); parent.value = next;
    }
    struct stat st{};
    if (fstat(parent.value, &st) || st.st_uid != getuid() || (st.st_mode & 0022)) fail();
    int result = openat(parent.value, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (result < 0 && errno == ENOENT && create) {
        if (mkdirat(parent.value, leaf, 0700) && errno != EEXIST) fail();
        result = openat(parent.value, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    }
    if (result < 0) { if (errno == ENOENT) return -1; fail(); }
    Fd checked; checked.value = result; private_entry(result, true);
    checked.value = -1; return result;
}
std::string hex(const unsigned char* bytes, size_t size) {
    const char alphabet[] = "0123456789abcdef";
    std::string out;
    for (size_t i = 0; i < size; ++i) {
        out += alphabet[bytes[i] >> 4]; out += alphabet[bytes[i] & 15];
    }
    return out;
}
std::string filename(const std::string& id) {
    cie_pairing::checkId(id);
    unsigned char digest[32]; unsigned n = 0;
    if (!EVP_Digest(id.data(), id.size(), digest, &n, EVP_sha256(), nullptr) || n != 32) fail();
    return hex(digest, n) + ".der";
}
void certificate(const uint8_t* der, uint32_t size) {
    if (!der || !size || size > 8192) fail();
    const auto* p = der;
    X509* cert = d2i_X509(nullptr, &p, size);
    EVP_PKEY* key = cert ? X509_get_pubkey(cert) : nullptr;
    const bool ok = cert && p == der + size && key &&
                    EVP_PKEY_is_a(key, "RSA") && EVP_PKEY_get_bits(key) == 2048;
    EVP_PKEY_free(key); X509_free(cert);
    if (!ok) fail();
    // This is only format validation. The Web engine binds the certificate to
    // the CIE/SOD during discovery/authentication before using its public key.
}
}
bool running() {
    const char* name = std::getenv("SNAP_NAME");
    const char* instance = std::getenv("SNAP_INSTANCE_NAME");
    return name && !std::strcmp(name, "firefox") &&
           (!instance || !std::strcmp(instance, "firefox"));
}
bool installed() {
    // A missing leaf does not imply a missing Snap installation.
    const auto path = common();
    Fd parent; parent.value = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (parent.value < 0) fail();
    for (const auto& component : path.relative_path()) {
        if (component == "." || component == "..") fail();
        int next = openat(parent.value, component.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) { if (errno == ENOENT) return false; fail(); }
        close(parent.value); parent.value = next;
    }
    struct stat st{};
    if (fstat(parent.value, &st) || st.st_uid != getuid() || (st.st_mode & 0022)) fail();
    return true;
}
std::vector<uint8_t> read(const std::string& id) {
    const auto name = filename(id);
    Fd dir; dir.value = directory(false); if (dir.value < 0) return {};
    Fd file; file.value = openat(dir.value, name.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (file.value < 0) { if (errno == ENOENT) return {}; fail(); }
    private_entry(file.value, false);
    struct stat st{}; if (fstat(file.value, &st) || st.st_size <= 0 || st.st_size > 8192) fail();
    std::vector<uint8_t> der(static_cast<size_t>(st.st_size));
    size_t offset = 0;
    while (offset < der.size()) {
        auto n = ::read(file.value, der.data() + offset, der.size() - offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) fail();
        offset += static_cast<size_t>(n);
    }
    uint8_t extra; if (::read(file.value, &extra, 1) != 0) fail();
    certificate(der.data(), static_cast<uint32_t>(der.size())); return der;
}
bool publish(const std::string& id, const uint8_t* der, uint32_t size) {
    const auto name = filename(id); certificate(der, size);
    Fd dir; dir.value = directory(true); if (dir.value < 0) return false;
    unsigned char nonce[16]; if (RAND_bytes(nonce, sizeof(nonce)) != 1) fail();
    const auto temp = ".tmp-" + hex(nonce, sizeof(nonce));
    try {
        Fd file; file.value = openat(dir.value, temp.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (file.value < 0) fail();
        private_entry(file.value, false);
        size_t offset = 0;
        while (offset < size) {
            auto n = ::write(file.value, der + offset, size - offset);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) fail();
            offset += static_cast<size_t>(n);
        }
        if (fsync(file.value) || renameat(dir.value, temp.c_str(), dir.value, name.c_str()) || fsync(dir.value)) fail();
    } catch (...) { unlinkat(dir.value, temp.c_str(), 0); throw; }
    return true;
}
bool matches_if_installed(const std::string& id, const uint8_t* der, uint32_t size) {
    if (!installed()) return true;
    return der && size && size <= 8192 && read(id) == std::vector<uint8_t>(der, der + size);
}
void erase(const std::string& id) {
    const auto name = filename(id);
    Fd dir; dir.value = directory(false); if (dir.value < 0) return;
    // unlinkat removes the directory entry itself, never follows a link or
    // touches another application's files. Only our hashed DER name is used.
    if (unlinkat(dir.value, name.c_str(), 0) && errno != ENOENT) fail();
    if (fsync(dir.value)) fail();
}
}
