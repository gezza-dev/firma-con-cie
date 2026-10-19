// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <openssl/x509.h>
#include <memory>
#include <cstdint>
#include <string>
namespace cie {
// Printed document number is the subject's IDCIT serialNumber, not the
// certificate serial, Common Name, tax code or internal IdServizi/PAN.
inline std::string certificateCardNumber(const uint8_t* der,size_t length){
 if(!der||!length||length>8192)return {};
 const auto* pos=der;
 std::unique_ptr<X509,decltype(&X509_free)> cert(d2i_X509(nullptr,&pos,long(length)),X509_free);
 if(!cert||pos!=der+length)return {};
 auto* subject=X509_get_subject_name(cert.get());
 auto index=X509_NAME_get_index_by_NID(subject,NID_serialNumber,-1);
 if(index<0||X509_NAME_get_index_by_NID(subject,NID_serialNumber,index)>=0)return {};
 unsigned char* bytes=nullptr;
 auto size=ASN1_STRING_to_UTF8(&bytes,X509_NAME_ENTRY_get_data(X509_NAME_get_entry(subject,index)));
 struct Free{unsigned char* p;~Free(){OPENSSL_free(p);}} free{bytes};
 if(!bytes||size!=15)return {};
 std::string value(reinterpret_cast<char*>(bytes),size);
 if(value.compare(0,6,"IDCIT-"))return {};
 auto number=value.substr(6);
 for(size_t i=0;i<9;++i)if(i>=2&&i<=6 ? number[i]<'0'||number[i]>'9' : number[i]<'A'||number[i]>'Z')return {};
 return number;
}
}
