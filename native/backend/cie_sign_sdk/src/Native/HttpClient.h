// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <curl/curl.h>
#include <cstdint>
#include <string>
#include <vector>
#include <chrono>
#include <memory>
#include <atomic>
#include <functional>

namespace cie {
struct HttpBudget {
    std::chrono::steady_clock::time_point deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(20);
    std::atomic<int> requests{12};
};
struct HttpResponse {
    int error = CURLE_FAILED_INIT;
    long status = 0;
    std::string redirect;
    std::vector<unsigned char> body;
};
struct HttpOptions {
    bool allowNetwork = true;
    bool head = false;
    // Internal protected-proxy transport state; never user/file configuration.
    bool followRedirects = true;
    std::string connectTo;
    bool publicAddressesOnly = false; // Untrusted document CRL URLs: check actual socket peers.
    std::shared_ptr<HttpBudget> budget;
    // Internal transport seam for deterministic security tests; never a file/FFI option.
    std::function<HttpResponse(const std::string&, const std::vector<unsigned char>&, const char*)> transport;
    std::string proxy;
    int proxyPort = 0;
    std::string proxyCredentials;
    std::string username;
    std::string password;
    ~HttpOptions(){for(auto* value:{&password,&proxyCredentials}){volatile char* p=value->empty()?nullptr:&(*value)[0];for(size_t i=0;i<value->size();++i)p[i]=0;}}
};
bool publicNetworkAddress(const unsigned char* bytes, size_t length);
// HTTP is needed by signed OCSP/CRL protocols. HTTPS always authenticates
// the peer and hostname using native platform trust; redirects cannot downgrade TLS.
HttpResponse httpRequest(const std::string& url, const std::vector<unsigned char>& body,
                         const char* contentType, const HttpOptions& options,
                         size_t maximumBytes = 32 * 1024 * 1024);
}
