// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>
namespace cie_cache {
// Plaintext and local encryption keys are erased on release, never logged.
struct Bytes : std::vector<uint8_t> {
 using std::vector<uint8_t>::vector;
 Bytes()=default;Bytes(const Bytes&)=delete;Bytes& operator=(const Bytes&)=delete;
 Bytes(Bytes&&)=default;Bytes& operator=(Bytes&&)=delete;
 ~Bytes(){volatile uint8_t* p=data();for(size_t i=0;i<size();++i)p[i]=0;}
};
void random(uint8_t*,size_t);
Bytes encrypt(const Bytes& key,const std::string& binding,const Bytes& plaintext);
Bytes decrypt(const Bytes& key,const std::string& binding,const Bytes& encoded);
// A transaction locks the private per-user directory across processes. Only
// the test build accepts an environment override; production never uses cwd.
class Store {
 struct Impl;Impl* impl_;
public:
 explicit Store(bool create=false);
 ~Store();Store(const Store&)=delete;Store& operator=(const Store&)=delete;
 void prepare();
 Bytes read(const std::string& kind,const std::string& id);
 void write(const std::string& kind,const std::string& id,const Bytes& bytes);
 void erase(const std::string& kind,const std::string& id);
 std::vector<std::string> list(const std::string& kind);
};
}
