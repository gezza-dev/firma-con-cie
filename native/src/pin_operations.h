// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstdint>
#include <cstring>
namespace cie_pin {
inline bool digits(const char* value) {
    if (!value || std::strlen(value)!=8) return false;
    for (int i=0;i<8;i++) if(value[i]<'0'||value[i]>'9') return false;
    return true;
}
inline bool newPin(const char* value) {
    return digits(value);
}
inline void wipe(char* value) {
    if(value) { size_t n=std::strlen(value);volatile char* p=value;while(n--) *p++=0; }
}
struct Secrets {
    char *authentication,*replacement;
    ~Secrets() { wipe(authentication);wipe(replacement); }
};
// phase 2 means the mutation was submitted but its response was not received.
// Never repeat either authentication or mutation after an exception.
template<class Session> int64_t update(Session& card,bool unblock,const char* expected,
                                      char* authentication,char* replacement,int& phase) {
    Secrets secrets{authentication,replacement};phase=0;
    if(!expected || !*expected || !digits(authentication) || !newPin(replacement)) return -1;
    try {
        if(card.id!=expected) return -10;
        card.secure();phase=1;
        auto status=card.verify(unblock,authentication);
        if(status!=0x9000) return status;
        phase=2;
        status=card.replace(unblock,authentication,replacement);
        phase=3;
        return status==0x9000 ? 0 : status;
    } catch(...) { return -2; }
}
}
