// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <openssl/x509.h>
#include <memory>
#include <string>
#include <stdexcept>
namespace cie {
inline std::string cardholderName(const unsigned char* der, size_t length) {
 if(!der || !length || length>8192)throw std::runtime_error("Missing card certificate");
 const auto* pos=der;
 std::unique_ptr<X509,decltype(&X509_free)> cert(d2i_X509(nullptr,&pos,long(length)),X509_free);
 if(!cert || pos!=der+length)throw std::runtime_error("Invalid card certificate");
 auto* subject=X509_get_subject_name(cert.get());
 auto field=[&](int nid){
  int index=X509_NAME_get_index_by_NID(subject,nid,-1);
  if(index<0 || X509_NAME_get_index_by_NID(subject,nid,index)>=0)throw std::runtime_error("Ambiguous cardholder name");
  unsigned char* bytes=nullptr;
  int size=ASN1_STRING_to_UTF8(&bytes,X509_NAME_ENTRY_get_data(X509_NAME_get_entry(subject,index)));
  struct Free{unsigned char* p;~Free(){OPENSSL_free(p);}} free{bytes};
  if(!bytes || size<=0 || size>240)throw std::runtime_error("Invalid cardholder name");
  std::string value(reinterpret_cast<char*>(bytes),size);
  for(unsigned char c:value)if(c<32 || c==127)throw std::runtime_error("Invalid cardholder name");
  auto first=value.find_first_not_of(' '),last=value.find_last_not_of(' ');
  if(first==std::string::npos)throw std::runtime_error("Empty cardholder name");
  return value.substr(first,last-first+1);
 };
 return field(NID_givenName)+" "+field(NID_surname);
}
}
