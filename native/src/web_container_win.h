// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <windows.h>
#include <wincrypt.h>
#include <stdexcept>
#include <string>
#include <cwchar>
#include <cstring>
namespace cie_web_store {
inline GUID containerGuid(const std::string& id){
 BYTE hash[32];DWORD size=sizeof(hash);
 if(!CryptHashCertificate(0,CALG_SHA_256,0,reinterpret_cast<const BYTE*>(id.data()),static_cast<DWORD>(id.size()),hash,&size)||size!=32)throw std::runtime_error("web_container");
 hash[6]=(hash[6]&15)|0x50;hash[8]=(hash[8]&63)|0x80;GUID guid;memcpy(&guid,hash,16);return guid;
}
inline std::wstring containerName(const GUID& g){
 wchar_t text[40];swprintf(text,40,L"%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",g.Data1,g.Data2,g.Data3,g.Data4[0],g.Data4[1],g.Data4[2],g.Data4[3],g.Data4[4],g.Data4[5],g.Data4[6],g.Data4[7]);return text;
}
}
