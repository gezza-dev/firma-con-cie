// SPDX-License-Identifier: BSD-3-Clause
#include "web_cert_store.h"
#include "local_cache.h"
#include "../snap_public_store.h"
#include "../../../../tests/fixtures/web_certificate.h"
#include <sys/stat.h>
#include <unistd.h>
#include <filesystem>
#include <chrono>
#include <cstring>
#include <cstdio>
#include <iostream>
#include <stdexcept>
static void check(bool value){if(!value)throw std::runtime_error("Linux public Web store regression");}
template<class F> static void rejects(F action){bool rejected=false;try{action();}catch(...){rejected=true;}check(rejected);}
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
    // Snap is not installed in this isolated test user yet. No directory or
    // browser configuration is created merely by preparing a certificate.
    check(!cie_linux_snap::installed());
    check(!std::filesystem::exists(root/"snap"));
    auto common=root/"snap/firefox/common";
    check(std::filesystem::create_directories(common));chmod(common.c_str(),0700);
    check(cie_linux_snap::installed());
    check(!cie_web_store::provisioned("TESTLINUXB",testCertificate,sizeof(testCertificate)));
    cie_web_store::write("TESTLINUXB",testCertificate,sizeof(testCertificate));
    check(cie_web_store::provisioned("TESTLINUXB",testCertificate,sizeof(testCertificate)));
    check(cie_linux_snap::read("TESTLINUXB")==cie_web_store::read("TESTLINUXB"));
    auto exported=common/"cie-id-web-v1";
    check(!stat(exported.c_str(),&st)&&(st.st_mode&0777)==0700);
    std::filesystem::path publicFile;
    for(auto& entry:std::filesystem::directory_iterator(exported)){
        check(entry.path().extension()==".der");
        check(entry.path().stem().string().size()==64);
        publicFile=entry.path();
    }
    check(!publicFile.empty()&&!stat(publicFile.c_str(),&st)&&(st.st_mode&0777)==0600);
    rejects([&]{cie_linux_snap::read("../invalid");});
    const uint8_t invalid[]={1,2,3};
    rejects([&]{cie_linux_snap::publish("TESTLINUXB",invalid,sizeof(invalid));});
    std::vector<uint8_t> trailing(std::begin(testCertificate),std::end(testCertificate));trailing.push_back(0);
    rejects([&]{cie_linux_snap::publish("TESTLINUXB",trailing.data(),trailing.size());});
    chmod(publicFile.c_str(),0644);rejects([&]{cie_linux_snap::read("TESTLINUXB");});
    cie_web_store::write("TESTLINUXB",testCertificate,sizeof(testCertificate));
    check(cie_web_store::provisioned("TESTLINUXB",testCertificate,sizeof(testCertificate)));
    auto link=root/"public-hardlink";std::filesystem::create_hard_link(publicFile,link);
    rejects([&]{cie_linux_snap::read("TESTLINUXB");});std::filesystem::remove(link);
    // Atomic repair replaces a symlink entry, never follows its target.
    auto target=root/"untouched";{FILE* f=fopen(target.c_str(),"wb");check(f);fputs("unchanged",f);fclose(f);}
    std::filesystem::remove(publicFile);std::filesystem::create_symlink(target,publicFile);
    rejects([&]{cie_linux_snap::read("TESTLINUXB");});
    cie_web_store::write("TESTLINUXB",testCertificate,sizeof(testCertificate));
    {char value[16]{};FILE* f=fopen(target.c_str(),"rb");check(f);check(fread(value,1,9,f)==9);fclose(f);check(!strcmp(value,"unchanged"));}
    chmod(exported.c_str(),0755);rejects([&]{cie_linux_snap::read("TESTLINUXB");});chmod(exported.c_str(),0700);
    auto backup=common/"original-public";std::filesystem::rename(exported,backup);
    std::filesystem::create_directory_symlink(backup,exported);
    rejects([&]{cie_linux_snap::read("TESTLINUXB");});
    rejects([&]{cie_linux_snap::publish("TESTLINUXB",testCertificate,sizeof(testCertificate));});
    std::filesystem::remove(exported);std::filesystem::rename(backup,exported);
    cie_web_store::write("TESTLINUXA",testCertificate,sizeof(testCertificate));
    cie_web_store::erase("TESTLINUXA");check(cie_linux_snap::read("TESTLINUXA").empty());
    check(!cie_linux_snap::read("TESTLINUXB").empty());
    check(!std::filesystem::exists(exported/".key"));
    for(auto& entry:std::filesystem::directory_iterator(exported))check(entry.path().extension()==".der");
    check(cie_web_store::test("TESTLINUXB")!=0);
    cie_web_store::erase("TESTLINUXB");check(cie_web_store::list().empty());
    check(cie_linux_snap::read("TESTLINUXB").empty());
    std::cout<<"Linux public Web store: independent namespace, certificate persistence/removal, permissions, no browser/card operations passed\n";return 0;
}catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}
