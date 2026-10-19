// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstddef>
#include <openssl/evp.h>
#include <vector>
namespace cie {
bool recoverRsaPkcs1(EVP_PKEY* publicKey, const unsigned char* signature,
                     std::size_t signatureLength, std::vector<unsigned char>& payload);
// Recover a PKCS#1 v1.5 type-1 payload using the certificate's public key.
// Returns false for malformed keys, wrong signature length or invalid padding.
bool recoverRsaPkcs1(const unsigned char *modulus, std::size_t modulusLength,
                     const unsigned char *exponent, std::size_t exponentLength,
                     const unsigned char *signature, std::size_t signatureLength,
                     std::vector<unsigned char>& payload);
}
