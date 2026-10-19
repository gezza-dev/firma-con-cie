// SPDX-License-Identifier: BSD-3-Clause
// Native digest adapter for the independent fork. No legacy hash implementation.
#pragma once
#include "../../../native/OpenSslRuntime.h"
#include <openssl/evp.h>
#include <array>
#include <cstddef>
#include <memory>
#include <stdexcept>

namespace cie {
inline void digest(const EVP_MD *algorithm, const unsigned char *data,
                   std::size_t length, unsigned char *output)
{
    if (!algorithm || !output || (!data && length))
        throw std::invalid_argument("Invalid digest arguments");
    if (!initializeOpenSsl()) throw std::runtime_error("OpenSSL providers unavailable");
    unsigned int written = 0;
    if (EVP_Digest(data, length, output, &written, algorithm, nullptr) != 1 ||
        written != static_cast<unsigned int>(EVP_MD_size(algorithm)))
        throw std::runtime_error("OpenSSL digest failed");
}
inline void digestSHA2(const unsigned char *data, std::size_t length,
                       unsigned char *output, int sha224)
{
    if (sha224 != 0 && sha224 != 1) throw std::invalid_argument("Invalid SHA-2 variant");
    digest(sha224 ? EVP_sha224() : EVP_sha256(), data, length, output);
}

// Words are exposed only for callers that serialize the digest as hexadecimal.
// They always represent the five big-endian words of a 20-byte SHA-1 digest.
class Sha1Digest {
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context_;
    bool finished_ = false;
public:
    std::array<unsigned int, 5> words{};
    Sha1Digest() : context_(EVP_MD_CTX_new(), EVP_MD_CTX_free) { reset(); }
    void reset() {
        if (!initializeOpenSsl() || !context_ || EVP_DigestInit_ex(context_.get(), EVP_sha1(), nullptr) != 1)
            throw std::runtime_error("SHA-1 initialization failed");
        words.fill(0);
        finished_ = false;
    }
    void update(const unsigned char *data, std::size_t length) {
        if (finished_ || (!data && length)) throw std::invalid_argument("Invalid SHA-1 input state");
        if (EVP_DigestUpdate(context_.get(), data, length) != 1)
            throw std::runtime_error("SHA-1 update failed");
    }
    int finish() {
        if (!finished_) {
            std::array<unsigned char, 20> bytes{};
            unsigned int length = 0;
            if (EVP_DigestFinal_ex(context_.get(), bytes.data(), &length) != 1 || length != bytes.size())
                throw std::runtime_error("SHA-1 finalization failed");
            for (std::size_t i = 0; i < words.size(); ++i) {
                words[i] = (static_cast<unsigned int>(bytes[4*i]) << 24) |
                    (static_cast<unsigned int>(bytes[4*i+1]) << 16) |
                    (static_cast<unsigned int>(bytes[4*i+2]) << 8) | bytes[4*i+3];
            }
            finished_ = true;
        }
        return 1;
    }
};
}
