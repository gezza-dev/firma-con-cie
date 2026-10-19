// SPDX-License-Identifier: BSD-3-Clause
#include "HttpClient.h"
#include "NetworkConfig.h"
#include <iostream>
#include <string>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif
// A private, bounded GET transport. CRL authentication is performed by the
// shared validator, never inferred from HTTP success. No document or PIN input.
int main(int argc, char** argv)
{
    try {
        if ((argc != 3 && !(argc==4&&std::string(argv[3])=="--network-stdin")) || std::string(argv[1]).size() > 2048) return 2;
        std::string value(argv[2]); size_t end = 0;
        int milliseconds = std::stoi(value, &end);
        if (end != value.size() || milliseconds < 1 || milliseconds > 10000) return 2;
        cie::HttpOptions options; options.publicAddressesOnly = true;
        if(argc==4){
#ifdef _WIN32
          _setmode(_fileno(stdin),_O_BINARY);
#endif
          auto network=cie::NetworkConfig::read(std::cin);options.proxy=network.endpoint();options.proxyPort=network.port;options.proxyCredentials=network.credentials();
        }
        options.budget = std::make_shared<cie::HttpBudget>(); options.budget->requests = options.proxy.empty()?1:4;
        options.budget->deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(milliseconds);
        auto response = cie::httpRequest(argv[1], {}, nullptr, options, 24 * 1024 * 1024);
        if (response.error != CURLE_OK || response.status != 200 || response.body.empty()) return 3;
#ifdef _WIN32
        _setmode(_fileno(stdout), _O_BINARY);
#endif
        std::cout.write(reinterpret_cast<const char*>(response.body.data()),response.body.size());
        return std::cout.good() ? 0 : 4;
    } catch (...) { return 2; }
}
