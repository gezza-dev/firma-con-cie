// SPDX-License-Identifier: BSD-3-Clause
#include "../cie-pkcs11/CSP/VerificaConCIE.h"
#include <dlfcn.h>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <type_traits>

static_assert(std::is_same<getVerifyInfofn, decltype(&getVerifyInfo)>::value,
              "UI callback ABI must match the middleware's output pointer");

static void require(bool value, const char* message)
{
    if (!value) throw std::runtime_error(message);
}

int main(int argc, char** argv)
{
    try {
        require(argc == 3, "Fixture directory or middleware path missing");
        void *module = dlopen(argv[2], RTLD_LOCAL | RTLD_NOW);
        require(module != nullptr, "Could not load the requested middleware");
        auto details = reinterpret_cast<getVerifyInfofn>(dlsym(module, "getVerifyInfo"));
        auto verify = reinterpret_cast<verificaConCIEfn>(dlsym(module, "verificaConCIE"));
        auto numberOfSigns = reinterpret_cast<decltype(&getNumberOfSign)>(dlsym(module, "getNumberOfSign"));
        require(details && verify && numberOfSigns, "Missing UI verification callbacks");
        verifyInfo_t info = {};
        require(numberOfSigns() == 0 && details(0, &info) == CKR_ARGUMENTS_BAD,
                "Uninitialized verification result must not be readable");
        auto check = [&](const char* name, bool valid, int count = 1) {
            std::string path = std::string(argv[1]) + "/" + name;
            require(verify(path.c_str(), nullptr, 0, nullptr) == (CK_RV)count,
                    "Wrong signature count returned to the UI");
            require(numberOfSigns() == (CK_RV)count, "Wrong stored signature count");
            for (int i = 0; i < count; ++i) {
                std::memset(&info, 0xA5, sizeof(info));
                require(details(i, &info) == CKR_OK, "Could not read verification details");
                require(std::strcmp(info.cn, "SDK integration test") == 0,
                        "Signer name corrupted across the UI/middleware ABI");
                require(info.isSignValid == valid, "Wrong cryptographic verification result");
                require(info.isCertValid, "Current certificate was classified as invalid");
                require(info.CertRevocStatus == REVOCATION_STATUS_UNKNOWN,
                        "A certificate without revocation endpoints must have unknown status");
            }
            require(details(-1, &info) == CKR_ARGUMENTS_BAD &&
                    details(count, &info) == CKR_ARGUMENTS_BAD &&
                    details(0, nullptr) == CKR_ARGUMENTS_BAD, "Invalid detail request accepted");
        };
        check("valid.pdf", true);
        check("tampered.pdf", false);
        check("two-signatures.pdf", true, 2);
        check("valid.p7m", true);
        check("tampered.p7m", false);
        check("unsigned.pdf", false, 0);
        require(verify(nullptr, nullptr, 0, nullptr) == DISIGON_ERROR_INVALID_FILE &&
                numberOfSigns() == 0, "Invalid input returned stale results");
        std::string missing = std::string(argv[1]) + "/missing.pdf";
        require(verify(missing.c_str(), nullptr, 0, nullptr) == DISIGON_ERROR_FILE_NOT_FOUND &&
                numberOfSigns() == 0, "Missing file returned stale results");
        check("valid.pdf", true); // Recovery after errors, including result ownership/cleanup.
        std::cout << "UI/middleware verification ABI, valid/tampered PDF and CMS, multiple signatures, "
                     "unknown revocation and error recovery passed\n";
        dlclose(module);
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
