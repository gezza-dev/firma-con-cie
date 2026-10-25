// SPDX-License-Identifier: BSD-3-Clause
// External test tool only: production Store persistence, synthetic bytes, no card.
#include "local_cache.h"
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <stdexcept>

int main(int argc, char** argv) {
    try {
        const char* id = std::getenv("FLATPAK_ID");
        if (argc != 2 || !id || std::string(id) != "it.giancarloezza.FirmaConCIE.Test" ||
            !std::filesystem::exists("/.flatpak-info"))
            throw std::runtime_error("Flatpak test sandbox required");
        const std::string action(argv[1]);
        if (action != "write" && action != "read" && action != "erase")
            throw std::runtime_error("Unknown probe action");
        cie_cache::Store store(action == "write");
        const std::string key = "SYNTHETICFLATPAKTEST";
        const cie_cache::Bytes expected{'s', 'y', 'n', 't', 'h', 'e', 't', 'i', 'c'};
        if (action == "write") store.write("card", key, expected);
        else if (action == "read") {
            if (store.read("card", key) != expected)
                throw std::runtime_error("Synthetic record did not persist");
        } else store.erase("card", key);
        std::cout << "FLATPAK_STORE_" << action << "_OK\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
