// SPDX-License-Identifier: BSD-3-Clause
#include "RsaRecovery.h"
#include "../../../native/OpenSslRuntime.h"
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/param_build.h>
#include <openssl/rsa.h>
#include <climits>
#include <memory>

bool cie::recoverRsaPkcs1(EVP_PKEY* publicKey, const unsigned char* signature,
                         std::size_t signatureLength, std::vector<unsigned char>& payload)
{
    payload.clear();
    if (!initializeOpenSsl() || !publicKey || !signature || !EVP_PKEY_is_a(publicKey, "RSA") ||
        signatureLength != static_cast<std::size_t>(EVP_PKEY_get_size(publicKey))) return false;
    std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)> context(
        EVP_PKEY_CTX_new_from_pkey(nullptr, publicKey, nullptr), EVP_PKEY_CTX_free);
    std::size_t length = 0;
    if (!context || EVP_PKEY_verify_recover_init(context.get()) != 1 ||
        EVP_PKEY_CTX_set_rsa_padding(context.get(), RSA_PKCS1_PADDING) != 1 ||
        EVP_PKEY_verify_recover(context.get(), nullptr, &length, signature, signatureLength) != 1) return false;
    std::vector<unsigned char> recovered(length);
    if (EVP_PKEY_verify_recover(context.get(), recovered.data(), &length, signature, signatureLength) != 1) return false;
    recovered.resize(length);
    payload.swap(recovered);
    return true;
}

bool cie::recoverRsaPkcs1(const unsigned char *modulus, std::size_t modulusLength,
                         const unsigned char *exponent, std::size_t exponentLength,
                         const unsigned char *signature, std::size_t signatureLength,
                         std::vector<unsigned char>& payload)
{
    payload.clear();
    if (!initializeOpenSsl() || !modulus || !exponent || !signature || !modulusLength || !exponentLength ||
        modulusLength > INT_MAX || exponentLength > INT_MAX) return false;
    std::unique_ptr<BIGNUM, decltype(&BN_free)> n(BN_bin2bn(modulus, static_cast<int>(modulusLength), nullptr), BN_free);
    std::unique_ptr<BIGNUM, decltype(&BN_free)> e(BN_bin2bn(exponent, static_cast<int>(exponentLength), nullptr), BN_free);
    if (!n || !e || BN_is_zero(n.get()) || !BN_is_odd(n.get()) ||
        BN_is_zero(e.get()) || BN_is_one(e.get()) || !BN_is_odd(e.get())) return false;
    std::unique_ptr<OSSL_PARAM_BLD, decltype(&OSSL_PARAM_BLD_free)> builder(OSSL_PARAM_BLD_new(), OSSL_PARAM_BLD_free);
    if (!builder || !OSSL_PARAM_BLD_push_BN(builder.get(), OSSL_PKEY_PARAM_RSA_N, n.get()) ||
        !OSSL_PARAM_BLD_push_BN(builder.get(), OSSL_PKEY_PARAM_RSA_E, e.get())) return false;
    std::unique_ptr<OSSL_PARAM, decltype(&OSSL_PARAM_free)> parameters(OSSL_PARAM_BLD_to_param(builder.get()), OSSL_PARAM_free);
    std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)> context(
        EVP_PKEY_CTX_new_from_name(nullptr, "RSA", nullptr), EVP_PKEY_CTX_free);
    EVP_PKEY* imported = nullptr;
    if (!parameters || !context || EVP_PKEY_fromdata_init(context.get()) != 1 ||
        EVP_PKEY_fromdata(context.get(), &imported, EVP_PKEY_PUBLIC_KEY, parameters.get()) != 1) return false;
    std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> key(imported, EVP_PKEY_free);
    return recoverRsaPkcs1(key.get(), signature, signatureLength, payload);
}
