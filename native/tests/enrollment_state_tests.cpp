// SPDX-License-Identifier: BSD-3-Clause
#include "card_observation.h"
#include "enrollment_record.h"
#include <iostream>
#include <stdexcept>
static int checks=0;
void require(bool value){++checks;if(!value)throw std::runtime_error("enrollment observation/record invariant failed");}
int main(){try{
 cie::CardObservation state;auto now=std::chrono::steady_clock::now();state.update("reader:1:atr");
 require(!state.shouldIdentify(false,false,now));require(!state.shouldIdentify(true,true,now));require(state.shouldIdentify(true,false,now));
 state.identified(0,"CARD",now);require(!state.shouldIdentify(true,false,now+std::chrono::minutes(1)));require(state.id=="CARD");
 state.update("reader:1:atr");require(state.id=="CARD");state.update("reader:3:atr");require(state.id.empty());require(state.shouldIdentify(true,false,now));
 state.identified(-3,"",now);require(!state.shouldIdentify(true,false,now+std::chrono::seconds(2)));require(state.shouldIdentify(true,false,now+std::chrono::seconds(3)));require(!state.shouldIdentify(true,true,now+std::chrono::seconds(5)));
 state.identified(-4,"",now);require(!state.shouldIdentify(true,false,now+std::chrono::minutes(1)));state.update("removed");require(!state.notCie);
 CieEnrollmentMaterial material{};material.size=sizeof(material);material.version=2;std::strcpy(material.fullName,u8"Léa D'Amico");material.certificateLength=3;material.certificate[0]=0x30;material.certificate[1]=1;
 auto bytes=cie::encodeEnrollment(material);auto decoded=cie::decodeEnrollment(bytes);require(decoded.version==2);require(std::string(decoded.fullName)==material.fullName);require(decoded.certificateLength==3);require(std::memcmp(decoded.certificate,material.certificate,3)==0);
 auto reject=[&](auto operation){bool rejected=false;try{operation();}catch(...){rejected=true;}require(rejected);};
 reject([&]{cie::decodeEnrollment({});});auto bad=bytes;bad[6]='3';reject([&]{cie::decodeEnrollment(bad);});bad=bytes;bad.push_back(0);reject([&]{cie::decodeEnrollment(bad);});bad=bytes;bad[8]=255;reject([&]{cie::decodeEnrollment(bad);});bad=bytes;bad[12]=0;reject([&]{cie::decodeEnrollment(bad);});material.version=1;reject([&]{cie::encodeEnrollment(material);});material.version=2;material.certificateLength=8193;reject([&]{cie::encodeEnrollment(material);});
 std::cout<<"ENROLLMENT_STATE_CHECKS="<<checks<<"\nNo PC/SC or credential access\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
