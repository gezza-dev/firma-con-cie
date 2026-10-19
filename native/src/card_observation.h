// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <chrono>
#include <string>
namespace cie {
// A presence epoch includes the PC/SC insertion counter and ATR, not transient
// INUSE flags. No certificate, PIN or private card context is cached here.
struct CardObservation {
 std::string epoch,id;bool attempted=false,notCie=false;
 std::chrono::steady_clock::time_point retry{};
 void update(const std::string& value){if(epoch!=value){epoch=value;id.clear();attempted=false;notCie=false;retry={};}}
 bool shouldIdentify(bool present,bool occupied,std::chrono::steady_clock::time_point now)const{return present&&!occupied&&id.empty()&&!notCie&&(!attempted||now>=retry);}
 void identified(int code,const char* card,std::chrono::steady_clock::time_point now){attempted=true;notCie=code==-4;if(code==0)id=card;retry=now+std::chrono::seconds(3);}
};
}
