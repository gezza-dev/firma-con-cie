// SPDX-License-Identifier: BSD-3-Clause
// Explicit Windows-only test. Synthetic end-entity certificate, test namespace,
// no trusted roots, no real CIE, no PIN, no driver registration.
#include "web_cert_store.h"
#include "paired_store.h"
#include <windows.h>
#include <wincrypt.h>
#include <iostream>
#include <stdexcept>
#include <cstring>
#include <filesystem>
#include <chrono>
static int checks=0;
static void check(bool value){++checks;if(!value)throw std::runtime_error("web certificate store check "+std::to_string(checks));}
#include "windows_public_certificate_fixture.h"
static constexpr const char* testId="TESTWEBCERT00001";
struct Fixture {
 PCCERT_CONTEXT cert=nullptr,original=nullptr;
 HCERTSTORE store=nullptr;
 ~Fixture(){try{cie_web_store::erase(testId);}catch(...){}
  if(original)CertDeleteCertificateFromStore(original);if(store)CertCloseStore(store,0);
  if(cert)CertFreeCertificateContext(cert);}
 unsigned count(){auto fresh=CertOpenStore(CERT_STORE_PROV_SYSTEM_W,0,0,CERT_SYSTEM_STORE_CURRENT_USER,L"MY");check(fresh!=nullptr);unsigned n=0;PCCERT_CONTEXT c=nullptr;while((c=CertEnumCertificatesInStore(fresh,c)))if(c->cbCertEncoded==cert->cbCertEncoded&&!memcmp(c->pbCertEncoded,cert->pbCertEncoded,c->cbCertEncoded))++n;CertCloseStore(fresh,0);return n;}
};
int main(){try{
 auto isolated=std::filesystem::temp_directory_path()/("cie-web-file-tests-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
 check(std::filesystem::create_directory(isolated));
 struct Cleanup{std::filesystem::path p;~Cleanup(){std::error_code ec;std::filesystem::remove_all(p,ec);}} cleanup{isolated};
 check(_wputenv_s(L"CIE_PAIRING_TEST_CACHE",isolated.c_str())==0);
 check(std::string(cie_pairing::service).find(".tests.")!=std::string::npos);
 Fixture f;cie_web_store::erase(testId);
 f.cert=CertCreateCertificateContext(X509_ASN_ENCODING,testCertificate,sizeof(testCertificate));check(f.cert!=nullptr);
 f.store=CertOpenStore(CERT_STORE_PROV_SYSTEM_W,0,0,CERT_SYSTEM_STORE_CURRENT_USER,L"MY");check(f.store!=nullptr);
 // An untagged context simulates a pre-existing official association. Refuse
 // enrollment before changing either that context or the credential store.
 check(CertAddCertificateContextToStore(f.store,f.cert,CERT_STORE_ADD_ALWAYS,&f.original)!=0);check(f.count()==1);
 bool conflict=false;try{cie_web_store::write(testId,f.cert->pbCertEncoded,f.cert->cbCertEncoded);}catch(const std::exception& e){conflict=std::string(e.what())=="web_certificate_conflict";}
 check(conflict);check(f.count()==1);check(cie_web_store::read(testId).empty());
 auto fresh=CertOpenStore(CERT_STORE_PROV_SYSTEM_W,0,0,CERT_SYSTEM_STORE_CURRENT_USER,L"MY");check(fresh!=nullptr);
 auto existing=CertFindCertificateInStore(fresh,X509_ASN_ENCODING,0,CERT_FIND_EXISTING,f.cert,nullptr);check(existing!=nullptr);
 DWORD propertySize=0;check(!CertGetCertificateContextProperty(existing,CERT_FIRST_USER_PROP_ID+71,nullptr,&propertySize));
 check(!CertGetCertificateContextProperty(existing,CERT_KEY_PROV_INFO_PROP_ID,nullptr,&propertySize));
 CertFreeCertificateContext(existing);CertCloseStore(fresh,0);
 check(CertDeleteCertificateFromStore(f.original)!=0);f.original=nullptr;check(f.count()==0);
 cie_web_store::write(testId,f.cert->pbCertEncoded,f.cert->cbCertEncoded);check(f.count()==1);
 auto read=cie_web_store::read(testId);check(read.size()==f.cert->cbCertEncoded&&!memcmp(read.data(),f.cert->pbCertEncoded,read.size()));
 cie_web_store::write(testId,f.cert->pbCertEncoded,f.cert->cbCertEncoded);check(f.count()==1);
 cie_web_store::erase(testId);check(cie_web_store::read(testId).empty());check(f.count()==0);
 std::cout<<checks<<" Windows public certificate store checks passed\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
