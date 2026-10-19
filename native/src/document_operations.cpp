// SPDX-License-Identifier: BSD-3-Clause
#include "cie_bridge.h"
#include "pdf_appearance.h"
#include "card_number.h"
#include "../backend/cie_sign_sdk/src/Native/CardholderName.h"
#include "../backend/cie_sign_sdk/src/Native/CadesCosign.h"
#include <podofo/podofo.h>
#include <filesystem>
#include <fstream>
#include <vector>
#include <cstring>
#include <stdexcept>
namespace {
void load(PoDoFo::PdfMemDocument& document,const char* input,std::vector<char>& data) {
    if(!input || !*input) throw std::runtime_error("Missing PDF");
    std::ifstream file(std::filesystem::u8path(input),std::ios::binary|std::ios::ate);
    const auto size=file.tellg();
    if(!file || size<=0 || size>256*1024*1024) throw std::runtime_error("Invalid PDF size");
    data.resize(static_cast<size_t>(size));file.seekg(0);
    if(!file.read(data.data(),size)) throw std::runtime_error("Unreadable PDF");
    document.LoadFromBuffer(PoDoFo::bufferview(data.data(),data.size()));
}
void png(PoDoFo::PdfMemDocument& document,const char* input) {
    if(!input || !*input || std::strlen(input)>=256) throw std::runtime_error("Invalid PNG path");
    std::ifstream file(std::filesystem::u8path(input),std::ios::binary|std::ios::ate);
    auto size=file.tellg();if(!file || size<24 || size>10*1024*1024) throw std::runtime_error("Invalid PNG size");
    unsigned char header[24]={};file.seekg(0);file.read(reinterpret_cast<char*>(header),24);
    const unsigned char magic[]={137,80,78,71,13,10,26,10};
    if(!file || std::memcmp(header,magic,8) || std::memcmp(header+12,"IHDR",4)) throw std::runtime_error("PNG required");
    auto number=[&](int i){return (uint32_t(header[i])<<24)|(uint32_t(header[i+1])<<16)|(uint32_t(header[i+2])<<8)|header[i+3];};
    uint64_t w=number(16),h=number(20);
    if(!w || !h || w>8192 || h>8192 || w*h>16*1024*1024) throw std::runtime_error("PNG dimensions exceeded");
    std::vector<char> encoded(static_cast<size_t>(size));file.seekg(0);
    if(!file.read(encoded.data(),size)) throw std::runtime_error("Unreadable PNG");
    auto image=document.CreateImage();image->LoadFromBuffer(PoDoFo::bufferview(encoded.data(),encoded.size())); // Decode before authentication.
}
}
extern "C" CIE_EXPORT int cie_document_pdf_info(const char* input,int page,CiePdfPageInfo* info) {
    if(!info || info->size!=sizeof(*info)) return -1;
    try {
        std::vector<char> data;PoDoFo::PdfMemDocument document;load(document,input,data);
        info->pageCount=static_cast<int>(document.GetPages().GetCount());
        if(page<0 || page>=info->pageCount) return -2;
        auto& p=document.GetPages().GetPageAt(page);auto box=p.GetCropBox();
        info->width=box.Width;info->height=box.Height;info->rotation=p.GetRotation();
        if(info->width<=0 || info->height<=0 || (info->rotation!=0 && info->rotation!=90 && info->rotation!=180 && info->rotation!=270)) return -2;
        return 0;
    } catch(...) { return -2; }
}
extern "C" CIE_EXPORT int cie_document_prepare_appearance(const char* input,const CiePdfAppearance* appearance,CiePdfAppearance* raw) {
    if(!appearance || !raw || !cie_pdf::valid(*appearance)) return -1;
    try {
        std::vector<char> data;PoDoFo::PdfMemDocument document;load(document,input,data);
        if(appearance->page>=static_cast<int>(document.GetPages().GetCount())) return -2;
        auto& page=document.GetPages().GetPageAt(appearance->page);
        auto rotation=page.GetRotation();if(rotation!=0 && rotation!=90 && rotation!=180 && rotation!=270) return -2;
        if(std::strcmp(appearance->imagePath,CIE_PDF_CARDHOLDER_NAME))png(document,appearance->imagePath);
        *raw=*appearance;return 0;
    } catch(...) { return -2; }
}

namespace {
cie::cades::Bytes readCms(const char* path){
 if(!path)throw std::runtime_error("Missing P7M");std::ifstream f(std::filesystem::u8path(path),std::ios::binary|std::ios::ate);auto n=f.tellg();
 if(!f||n<=0||n>256*1024*1024)throw std::runtime_error("Invalid CMS size");std::vector<char> data(static_cast<size_t>(n));f.seekg(0);if(!f.read(data.data(),n))throw std::runtime_error("Unreadable CMS");return cie::cades::canonical(data.data(),data.size());
}
}
extern "C" CIE_EXPORT int cie_document_p7m_info(const char* input,uint32_t* count){try{auto cms=readCms(input);cie::cades::content(cms);if(!count)return -1;*count=cie::cades::count(cms);return *count<64?0:-1;}catch(...){return -1;}}
extern "C" CIE_EXPORT int cie_document_p7m_preserved(const char* input,const char* output){try{return cie::cades::preserves(readCms(input),readCms(output))?0:-1;}catch(...){return -1;}}

#include "cie_network_types.h"
#include "NetworkConfig.h"
#include "../backend/cie_sign_sdk/src/Native/HttpClient.h"
extern "C" CIE_EXPORT int cie_document_network_probe(const CieNetworkOptions* raw,CieNetworkProbe* out){
 try{if(!out||out->size!=sizeof(*out)||!raw||raw->size!=sizeof(*raw))return -1;
  auto config=cie::NetworkConfig::from(raw->mode,raw->host,raw->port,raw->username,raw->password);
  cie::HttpOptions options;options.proxy=config.endpoint();options.proxyPort=config.port;options.proxyCredentials=config.credentials();options.head=true;
  auto response=cie::httpRequest("https://www.cartaidentita.interno.gov.it/",{},nullptr,options,1024);
  out->transport_code=response.error;out->http_status=response.status;return 0;
 }catch(...){return -1;}
}

extern "C" CIE_EXPORT int cie_document_certificate_name(const uint8_t* der,uint32_t size,char* name,uint32_t capacity){
 try{if(!name||!capacity)return -1;name[0]=0;auto text=cie::cardholderName(der,size);if(text.size()>=capacity)return -1;std::memcpy(name,text.c_str(),text.size()+1);return 0;}catch(...){return -1;}
}

extern "C" CIE_EXPORT int cie_document_certificate_card_number(const uint8_t* der,uint32_t size,char* number,uint32_t capacity){
 try{if(!number||!capacity)return -1;number[0]=0;auto text=cie::certificateCardNumber(der,size);if(text.empty()||text.size()>=capacity)return -1;std::memcpy(number,text.c_str(),text.size()+1);return 0;}catch(...){return -1;}
}
