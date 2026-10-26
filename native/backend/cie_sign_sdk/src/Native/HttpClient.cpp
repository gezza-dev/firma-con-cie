// SPDX-License-Identifier: BSD-3-Clause
#include "HttpClient.h"
#include <limits>
#include <memory>
#include <mutex>
#include <algorithm>
#include <condition_variable>
#include <thread>
#include <cctype>
#include <cstring>
#include "NetworkConfig.h"
#ifdef __linux__
#include "LinuxTlsTrust.h"
#endif
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#endif

namespace cie {
bool publicNetworkAddress(const unsigned char* b, size_t n)
{
    if (n == 4) {
        return b[0] != 0 && b[0] != 10 && b[0] != 127 && b[0] < 224 &&
            !(b[0] == 100 && (b[1] & 192) == 64) &&
            !(b[0] == 169 && b[1] == 254) && !(b[0] == 172 && (b[1] & 240) == 16) &&
            !(b[0] == 192 && (b[1] == 168 || b[1] == 0 || (b[1] == 88 && b[2] == 99))) &&
            !(b[0] == 198 && (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) &&
            !(b[0] == 203 && b[1] == 0 && b[2] == 113);
    }
    // Only global IPv6 unicast, excluding documentation and transition/tunnel ranges.
    if (n == 16) return (b[0] & 224) == 32 &&
        !(b[0] == 0x20 && b[1] == 0x01 && (b[2] == 0 || (b[2] == 0x0d && b[3] == 0xb8))) &&
        !(b[0] == 0x20 && b[1] == 0x02);
    return false;
}
namespace {
curl_socket_t publicSocket(void*, curlsocktype purpose, struct curl_sockaddr* a)
{
    if (purpose != CURLSOCKTYPE_IPCXN) return CURL_SOCKET_BAD;
    const unsigned char* bytes = nullptr; size_t count = 0;
    if (a->family == AF_INET) {
        auto* ip = reinterpret_cast<const sockaddr_in*>(&a->addr);
        bytes = reinterpret_cast<const unsigned char*>(&ip->sin_addr); count = 4;
    } else if (a->family == AF_INET6) {
        auto* ip = reinterpret_cast<const sockaddr_in6*>(&a->addr);
        bytes = reinterpret_cast<const unsigned char*>(&ip->sin6_addr); count = 16;
    }
    return bytes && publicNetworkAddress(bytes, count) ? ::socket(a->family,a->socktype,a->protocol) : CURL_SOCKET_BAD;
}
// Resolve an untrusted CRL host locally within a bounded wait. The proxy must
// CONNECT to this checked numeric address, so it cannot resolve it to a LAN host.
std::string publicTarget(const std::string& host,long milliseconds){
 struct Lookup {std::mutex lock;std::condition_variable ready;bool done=false;std::string address;};
 auto state=std::make_shared<Lookup>();
 std::thread([host,state]{
  addrinfo hints{};hints.ai_family=AF_UNSPEC;hints.ai_socktype=SOCK_STREAM;addrinfo* raw=nullptr;std::string address;bool valid=true;
  if(getaddrinfo(host.c_str(),nullptr,&hints,&raw)==0){
   std::unique_ptr<addrinfo,decltype(&freeaddrinfo)> list(raw,freeaddrinfo);
   for(auto* a=raw;a;a=a->ai_next){const void* bytes=nullptr;size_t size=0;
    if(a->ai_family==AF_INET){bytes=&reinterpret_cast<sockaddr_in*>(a->ai_addr)->sin_addr;size=4;}
    else if(a->ai_family==AF_INET6){bytes=&reinterpret_cast<sockaddr_in6*>(a->ai_addr)->sin6_addr;size=16;}
    if(!bytes||!publicNetworkAddress(static_cast<const unsigned char*>(bytes),size)){valid=false;break;}
    char text[INET6_ADDRSTRLEN]{};if(!inet_ntop(a->ai_family,bytes,text,sizeof(text))){valid=false;break;}
    if(address.empty())address=a->ai_family==AF_INET6?std::string("[")+text+"]":text;
   }
  }
  {std::lock_guard<std::mutex> guard(state->lock);state->address=valid?address:"";state->done=true;}state->ready.notify_one();
 }).detach();
 std::unique_lock<std::mutex> lock(state->lock);state->ready.wait_for(lock,std::chrono::milliseconds(std::min(2000L,milliseconds)),[&]{return state->done;});return state->done?state->address:"";
}
HttpResponse publicProxyRequest(const std::string& initial,const HttpOptions& options,size_t maximum){
 HttpResponse failure;failure.error=CURLE_COULDNT_CONNECT;
 std::string current=initial;bool https=false;
 for(int redirect=0;redirect<=3;redirect++){
  std::unique_ptr<CURLU,decltype(&curl_url_cleanup)> url(curl_url(),curl_url_cleanup);
  if(!url||curl_url_set(url.get(),CURLUPART_URL,current.c_str(),0)!=CURLUE_OK)return failure;
  auto part=[&](CURLUPart key,unsigned flags=0){char* p=nullptr;if(curl_url_get(url.get(),key,&p,flags)!=CURLUE_OK)return std::string();std::string value(p);curl_free(p);return value;};
  auto scheme=part(CURLUPART_SCHEME),host=part(CURLUPART_HOST),port=part(CURLUPART_PORT,CURLU_DEFAULT_PORT);
  if((scheme!="https"&&scheme!="http")||(https&&scheme!="https")||!part(CURLUPART_USER).empty()||current.size()>2048)return failure;
  https=scheme=="https";auto dnsHost=host;if(host.size()>2&&host.front()=='['&&host.back()==']')dnsHost=host.substr(1,host.size()-2);
  long remaining=2000;if(options.budget)remaining=std::chrono::duration_cast<std::chrono::milliseconds>(options.budget->deadline-std::chrono::steady_clock::now()).count();if(remaining<=0)return failure;
  auto target=publicTarget(dnsHost,remaining);if(target.empty())return failure;
  auto protectedOptions=options;protectedOptions.publicAddressesOnly=false;protectedOptions.followRedirects=false;protectedOptions.connectTo=host+":"+port+":"+target+":"+port;
  auto response=httpRequest(current,{},nullptr,protectedOptions,maximum);
  if(response.status>=300&&response.status<400&&!response.redirect.empty()){current=response.redirect;continue;}
  return response;
 }
 failure.error=CURLE_TOO_MANY_REDIRECTS;return failure;
}
struct Buffer { std::vector<unsigned char> bytes; size_t maximum; };
size_t receive(char* data, size_t size, size_t count, void* context)
{
    auto& output = *static_cast<Buffer*>(context);
    if (size && count > std::numeric_limits<size_t>::max() / size) return 0;
    size_t length = size * count;
    if (length > output.maximum - output.bytes.size()) return 0;
    try { output.bytes.insert(output.bytes.end(), data, data + length); }
    catch (...) { return 0; }
    return length;
}
}
HttpResponse httpRequest(const std::string& url, const std::vector<unsigned char>& body,
                         const char* contentType, const HttpOptions& options, size_t maximumBytes)
{
    HttpResponse result;
    long timeout = 10000;
    if (!options.allowNetwork) { result.error = CURLE_OPERATION_TIMEDOUT; return result; }
    if (options.budget && !(options.publicAddressesOnly && !options.proxy.empty())) {
        auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
            options.budget->deadline - std::chrono::steady_clock::now()).count();
        if (remaining <= 0 || options.budget->requests.fetch_sub(1) <= 0) {
            result.error = CURLE_OPERATION_TIMEDOUT; return result;
        }
        timeout = static_cast<long>(std::min<int64_t>(timeout, remaining));
    }
    if (options.transport) {
        auto reply = options.transport(url, body, contentType);
        if (reply.body.size() > maximumBytes) return result;
        return reply;
    }
    static std::once_flag initialized;
    static CURLcode globalStatus = CURLE_FAILED_INIT;
    std::call_once(initialized, [] { globalStatus = curl_global_init(CURL_GLOBAL_DEFAULT); });
    if (globalStatus != CURLE_OK) return result;
    if(options.publicAddressesOnly&&!options.proxy.empty()){
        // The public CRL helper is GET-only, never a generic proxy tunnel.
        if(!body.empty()||contentType)return result;
        return publicProxyRequest(url,options,maximumBytes);
    }
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> handle(curl_easy_init(), curl_easy_cleanup);
    std::unique_ptr<CURLU, decltype(&curl_url_cleanup)> address(curl_url(), curl_url_cleanup);
    if (!handle || !address || curl_url_set(address.get(), CURLUPART_URL, url.c_str(), 0) != CURLUE_OK) {
        result.error = CURLE_URL_MALFORMAT; return result;
    }
    char* rawScheme = nullptr;
    if (curl_url_get(address.get(), CURLUPART_SCHEME, &rawScheme, 0) != CURLUE_OK) return result;
    std::string scheme(rawScheme); curl_free(rawScheme);
    if (scheme != "http" && scheme != "https") { result.error = CURLE_UNSUPPORTED_PROTOCOL; return result; }
    // Do not transmit timestamp-service credentials over cleartext HTTP.
    if (scheme != "https" && (!options.username.empty() || !options.password.empty())) {
        result.error = CURLE_LOGIN_DENIED; return result;
    }
    char* user = nullptr;
    if (curl_url_get(address.get(), CURLUPART_USER, &user, 0) == CURLUE_OK) {
        curl_free(user); result.error = CURLE_URL_MALFORMAT; return result;
    }
    Buffer output{{}, maximumBytes};
    auto set = [&](CURLoption option, auto value) { return curl_easy_setopt(handle.get(), option, value) == CURLE_OK; };
#ifdef __linux__
    const auto trust = linuxTlsTrust();
    const char* caFile = trust.file.empty() ? nullptr : trust.file.c_str();
    const char* caDirectory = trust.directory.empty() ? nullptr : trust.directory.c_str();
    if (!set(CURLOPT_CAINFO, caFile) || !set(CURLOPT_CAPATH, caDirectory) ||
        !set(CURLOPT_PROXY_CAINFO, caFile) || !set(CURLOPT_PROXY_CAPATH, caDirectory)) return result;
#endif
    if (!set(CURLOPT_URL, url.c_str()) || !set(CURLOPT_SSL_VERIFYPEER, 1L) ||
        !set(CURLOPT_SSL_VERIFYHOST, 2L) || !set(CURLOPT_SSL_OPTIONS, long(CURLSSLOPT_NATIVE_CA)) ||
        !set(CURLOPT_SSLVERSION, long(CURL_SSLVERSION_TLSv1_2)) ||
        !set(CURLOPT_PROTOCOLS_STR, "http,https") ||
        !set(CURLOPT_REDIR_PROTOCOLS_STR, scheme == "https" ? "https" : "http,https") ||
        !set(CURLOPT_FOLLOWLOCATION, options.followRedirects?1L:0L) || !set(CURLOPT_MAXREDIRS, 3L) ||
        !set(CURLOPT_CONNECTTIMEOUT_MS, std::min(5000L, timeout)) || !set(CURLOPT_TIMEOUT_MS, timeout) ||
        !set(CURLOPT_NOSIGNAL, 1L) || !set(CURLOPT_FAILONERROR, 1L) ||
        !set(CURLOPT_WRITEFUNCTION, receive) || !set(CURLOPT_WRITEDATA, &output)) return result;
    // Empty proxy explicitly means a direct request, not a proxy inherited
    // from environment variables in a calling process.
    if (!set(CURLOPT_PROXY, options.proxy.c_str())) return result;
    if (!options.proxy.empty()) {
        auto proxy=options.proxy;
        const bool secure=proxy.rfind("https://",0)==0;
        if(proxy.rfind("http://",0)==0)proxy.erase(0,7);else if(secure)proxy.erase(0,8);
        if(!NetworkConfig::validHost(proxy)||options.proxyPort<1||options.proxyPort>65535||
            !set(CURLOPT_PROXYTYPE,long(secure?CURLPROXY_HTTPS:CURLPROXY_HTTP))||
            !set(CURLOPT_PROXYPORT,long(options.proxyPort))||!set(CURLOPT_NOPROXY, "")||
            !set(CURLOPT_PROXYAUTH,long(CURLAUTH_BASIC))||
            !set(CURLOPT_PROXY_SSL_VERIFYPEER,1L)||!set(CURLOPT_PROXY_SSL_VERIFYHOST,2L)||
            !set(CURLOPT_PROXY_SSL_OPTIONS,long(CURLSSLOPT_NATIVE_CA))||
            !set(CURLOPT_PROXY_SSLVERSION,long(CURL_SSLVERSION_TLSv1_2))||
            !set(CURLOPT_PROXYUSERPWD,options.proxyCredentials.c_str()))return result;
    }
    if(options.publicAddressesOnly&&!set(CURLOPT_OPENSOCKETFUNCTION,publicSocket))return result;
    std::unique_ptr<curl_slist,decltype(&curl_slist_free_all)> connection(nullptr,curl_slist_free_all);
    if(!options.connectTo.empty()){
        connection.reset(curl_slist_append(nullptr,options.connectTo.c_str()));
        if(!connection||!set(CURLOPT_CONNECT_TO,connection.get())||!set(CURLOPT_HTTPPROXYTUNNEL,1L))return result;
    }
    if(options.head&&!set(CURLOPT_NOBODY,1L))return result;
    if (!options.username.empty() || !options.password.empty()) {
        if (!set(CURLOPT_HTTPAUTH, long(CURLAUTH_BASIC)) || !set(CURLOPT_USERNAME, options.username.c_str()) ||
            !set(CURLOPT_PASSWORD, options.password.c_str())) return result;
    }
    if (!body.empty() && (!set(CURLOPT_POST, 1L) ||
        !set(CURLOPT_POSTFIELDSIZE_LARGE, curl_off_t(body.size())) ||
        !set(CURLOPT_POSTFIELDS, reinterpret_cast<const char*>(body.data())))) return result;
    std::unique_ptr<curl_slist, decltype(&curl_slist_free_all)> headers(nullptr, curl_slist_free_all);
    if (contentType) {
        std::string header = std::string("Content-Type: ") + contentType;
        headers.reset(curl_slist_append(nullptr, header.c_str()));
        if (!headers || !set(CURLOPT_HTTPHEADER, headers.get())) return result;
    }
    result.error = curl_easy_perform(handle.get());
    curl_easy_getinfo(handle.get(), CURLINFO_RESPONSE_CODE, &result.status);
    if(!options.followRedirects&&result.status>=300&&result.status<400){char* next=nullptr;curl_easy_getinfo(handle.get(),CURLINFO_REDIRECT_URL,&next);if(next&&std::strlen(next)<=2048)result.redirect=next;}
    if (result.error == CURLE_OK && result.status == 200) result.body = std::move(output.bytes);
    else if (result.error == CURLE_OK) result.error = CURLE_HTTP_RETURNED_ERROR;
    return result;
}
}
