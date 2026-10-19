// SPDX-License-Identifier: BSD-3-Clause
// Synthetic secure-session seam: never connects to PC/SC or uses real secrets.
#include "pin_operations.h"
#include <iostream>
#include <stdexcept>
#include <string>
struct Session {
    std::string id="TEST";
    int secureCalls=0,verifications=0,mutations=0,status=0x9000,mutationStatus=0x9000;
    bool throwSecure=false,throwVerify=false,throwMutation=false,sawPuk=false;
    void secure() { secureCalls++;if(throwSecure) throw 1; }
    int verify(bool puk,char*) { verifications++;sawPuk=puk;if(throwVerify) throw 1;return status; }
    int replace(bool puk,char*,char*) { mutations++;if(puk!=sawPuk) throw 1;if(throwMutation) throw 1;return mutationStatus; }
};
static void require(bool b) { if(!b) throw std::runtime_error("PIN workflow test failed"); }
int main() {
    int cases=0;
    auto run=[&](Session& s,bool puk,const char* expected,int64_t status,int phaseExpected,const char* old="10293847",const char* replacement="86420975") {
        char a[32]={},b[32]={};std::strcpy(a,old);std::strcpy(b,replacement);int phase=-1;
        auto result=cie_pin::update(s,puk,expected,a,b,phase);
        require(result==status && phase==phaseExpected);
        for(size_t i=0;i<std::strlen(old);i++) require(a[i]==0);
        for(size_t i=0;i<std::strlen(replacement);i++) require(b[i]==0);
        cases++;
    };
    for(bool puk:{false,true}) {
        Session good;run(good,puk,"TEST",0,3);require(good.secureCalls==1&&good.verifications==1&&good.mutations==1&&good.sawPuk==puk);
        Session changed;run(changed,puk,"OTHER",-10,0);require(changed.secureCalls==0&&changed.verifications==0&&changed.mutations==0);
        for(int status:{0x63C2,0x63C0,0x6983,0x6300}) { Session bad;bad.status=status;run(bad,puk,"TEST",status,1);require(bad.verifications==1&&bad.mutations==0); }
        Session secure;secure.throwSecure=true;run(secure,puk,"TEST",-2,0);require(secure.verifications==0);
        Session verify;verify.throwVerify=true;run(verify,puk,"TEST",-2,1);require(verify.verifications==1&&verify.mutations==0);
        Session uncertain;uncertain.throwMutation=true;run(uncertain,puk,"TEST",-2,2);require(uncertain.verifications==1&&uncertain.mutations==1);
        Session denied;denied.mutationStatus=0x6985;run(denied,puk,"TEST",0x6985,3);require(denied.mutations==1);
        for(const char* invalid:{"123","abcdefgh","123456789","12x45678"}) { Session bad;run(bad,puk,"TEST",-1,0,"10293847",invalid);require(bad.secureCalls==0); }
        for(const char* accepted:{"00000000","11111111","12345678","87654321","12121212"}) { Session good;run(good,puk,"TEST",0,3,"10293847",accepted);require(good.verifications==1&&good.mutations==1); }
    }
    Session same;run(same,false,"TEST",0,3,"10293847","10293847");require(same.verifications==1&&same.mutations==1);
    Session invalid;run(invalid,false,"TEST",-1,0,"bad");require(invalid.secureCalls==0);
    std::cout<<"PIN_WORKFLOW_CASES="<<cases<<"\n";
}
