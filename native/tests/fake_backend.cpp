// SPDX-License-Identifier: BSD-3-Clause
// Synthetic backend for ABI/error handling tests only, never used by the app.
#include "middleware_abi.h"
#include "cie_bridge.h"
#include <cstring>
#include <string>
#include <fstream>
#include <filesystem>
#include "pdf_appearance.h"
static unsigned long count = 0;
static bool rejectSignature=false;
extern "C" CIE_EXPORT void fake_reject_signature(int reject){rejectSignature=reject;}
static int networkCalls=0,networkBits=0;
extern "C" CIE_EXPORT int fake_network_calls(){return networkCalls;}
extern "C" CIE_EXPORT int fake_network_bits(){return networkBits;}
extern "C" CIE_EXPORT unsigned long verificaConCIE(const char* path, const char* host, int port, const char* credentials) {
    ++networkCalls;networkBits=(host&&std::strcmp(host,"https://proxy.test")==0?1:0)|(port==8443?2:0)|(credentials&&std::strcmp(credentials,"proxy-user:proxy-secret")==0?4:0);
    count = path && std::string(path).find("unsigned") == std::string::npos ? 1 : 0;
    return count;
}
extern "C" CIE_EXPORT unsigned long getNumberOfSign() { return count; }
extern "C" CIE_EXPORT unsigned long getVerifyInfo(int index, CieVerifyInfo* info) {
    if (!info || index != 0 || count != 1) return 7;
    *info = {};
    std::strcpy(info->cn, "Synthetic ABI test signer");
    info->isSignValid = !rejectSignature;
    info->isCertValid = true;
    info->CertRevocStatus = 3;
    return 0;
}
extern "C" CIE_EXPORT int cie_document_pdf_info(const char*,int page,CiePdfPageInfo* info) {
    if(!info || page<0 || page>=2)return -1;
    info->pageCount=2;info->rotation=page*90;info->width=600;info->height=800;return 0;
}
extern "C" CIE_EXPORT int cie_document_prepare_appearance(const char*,const CiePdfAppearance* a,CiePdfAppearance* raw) {
    if(!a || !raw || !cie_pdf::valid(*a) || a->page>=2 || std::strstr(a->imagePath,"invalid"))return -1;
    *raw=*a;return 0;
}
extern "C" CIE_EXPORT unsigned long estraiP7m(const char* source,const char* output) {
    if(std::strstr(source,"malformed"))return 7;
    std::ofstream(std::filesystem::u8path(output),std::ios::binary)<<"Synthetic extracted content";return 0;
}

extern "C" CIE_EXPORT int cie_document_p7m_info(const char* path,uint32_t* count){if(!path||!count||std::strstr(path,"malformed")||std::strstr(path,"detached"))return -1;*count=2;return 0;}
extern "C" CIE_EXPORT int cie_document_p7m_preserved(const char* input,const char*){return std::strstr(input,"lost-signature")?-1:0;}

extern "C" CIE_EXPORT int cie_document_network_probe(const CieNetworkOptions* config,CieNetworkProbe* result){if(!config||!result)return -1;result->transport_code=0;result->http_status=200;return 0;}
