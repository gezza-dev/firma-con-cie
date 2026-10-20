#include "cryptoki.h"
#include <dlfcn.h>
#include <iostream>
#include <cstring>

int main(int argc, char **argv)
{
    // Validate the real loaded module and ABI without touching a card or PIN.
    if (argc != 2 && argc != 3) { std::cerr << "Middleware path missing\n"; return 1; }
    void *glib = nullptr;
    if (argc == 3) {
        if (std::strcmp(argv[2], "--preload-glib")) return 1;
        glib = dlopen("libglib-2.0.so.0", RTLD_GLOBAL | RTLD_NOW);
        if (!glib) { std::cerr << dlerror() << '\n'; return 1; }
    }
    void *module = dlopen(argv[1], RTLD_LOCAL | RTLD_NOW);
    if (!module) { std::cerr << dlerror() << '\n'; return 1; }
    auto getFunctionList = reinterpret_cast<CK_RV (*)(CK_FUNCTION_LIST_PTR_PTR)>(
        dlsym(module, "C_GetFunctionList"));
    if (!getFunctionList) { std::cerr << dlerror() << '\n'; return 1; }
    CK_FUNCTION_LIST_PTR functions = NULL;
    if (getFunctionList(&functions) != CKR_OK || !functions ||
        functions->version.major != 2 || functions->version.minor != 20 ||
        !functions->C_Initialize || !functions->C_Finalize || !functions->C_Sign ||
        !functions->C_GetSlotList) {
        std::cerr << "Invalid PKCS#11 function table\n";
        return 1;
    }
    // Check the linked library, not just the headers used during compilation.
    auto opensslVersion = reinterpret_cast<unsigned long (*)()>(dlsym(module,"OpenSSL_version_num"));
    if (!opensslVersion || opensslVersion() != 0x30500090UL) {
        std::cerr << "Middleware does not embed OpenSSL 3.5.9 LTS\n";
        return 1;
    }
    // Uninitialized entry points must fail cleanly, with the correct CK_RV ABI.
    CK_INFO info = {};
    if (functions->C_GetInfo(&info) != CKR_CRYPTOKI_NOT_INITIALIZED) {
        std::cerr << "Unexpected uninitialized PKCS#11 state\n";
        return 1;
    }
    std::cout << "Native middleware exports, PKCS#11 ABI and OpenSSL 3.5.9 runtime passed\n";
    dlclose(module);
    if (glib) dlclose(glib);
    return 0;
}
