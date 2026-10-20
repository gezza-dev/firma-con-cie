// SPDX-License-Identifier: BSD-3-Clause
#include "web_cert_store.h"
#include "local_cache.h"
#include "../../../../tests/fixtures/web_certificate.h"
#include <sys/stat.h>
#include <unistd.h>
#include <filesystem>
#include <chrono>
#include <cstring>
#include <iostream>
#include <stdexcept>
static void check(bool value){if(!value)throw std::runtime_error("Linux public Web store regression");}
int main(){try{
    auto root=std::filesystem::temp_directory_path()/("cie-linux-web-public-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    check(std::filesystem::create_directory(root));chmod(root.c_str(),0700);
    struct Cleanup{std::filesystem::path p;~Cleanup(){std::error_code e;std::filesystem::remove_all(p,e);}} cleanup{root};
    setenv("CIE_PAIRING_TEST_CACHE",root.c_str(),1);
    // Metadata probe never invokes C_Initialize or accesses Firefox/PCSC.
    check(cie_web_store::componentAvailable());
    check(cie_web_store::list().empty());check(cie_web_store::read("TESTLINUXA").empty());
    check(!std::filesystem::exists(root/"cache-v3"));
    cie_web_store::write("TESTLINUXA",testCertificate,sizeof(testCertificate));
    cie_web_store::write("TESTLINUXB",testCertificate,sizeof(testCertificate));
    check(cie_web_store::provisioned("TESTLINUXA",testCertificate,sizeof(testCertificate)));
    check(cie_web_store::read("TESTLINUXA")==std::vector<uint8_t>(std::begin(testCertificate),std::end(testCertificate)));
    {cie_cache::Store store;check(store.list("card").empty());}
    cie_web_store::erase("TESTLINUXA");cie_web_store::erase("TESTLINUXA");
    check(cie_web_store::list()==std::vector<std::string>{"TESTLINUXB"});
    check(!cie_web_store::provisioned("TESTLINUXA",testCertificate,sizeof(testCertificate)));
    struct stat st{};check(!stat((root/"cache-v3/TESTLINUXB.web").c_str(),&st));
    check(st.st_uid==getuid()&&(st.st_mode&0777)==0600);
    check(cie_web_store::test("TESTLINUXB")!=0);
    cie_web_store::erase("TESTLINUXB");check(cie_web_store::list().empty());
    std::cout<<"Linux public Web store: independent namespace, certificate persistence/removal, permissions, no browser/card operations passed\n";return 0;
}catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}
