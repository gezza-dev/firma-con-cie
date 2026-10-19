// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "web_policy.h"
#include <algorithm>
#include <vector>
#include <utility>
namespace cie_web {
// Bind a single OS request to the result computed within the authenticated
// transaction. Contains only DigestInfo and public signature, never a PIN.
class SignRequest {
 enum class Phase { Empty, Pending, Authenticating, Ready, Consumed, Failed };
 Phase phase=Phase::Empty;
 std::vector<uint8_t> digest,signature;
public:
 SignRequest()=default;
 SignRequest(const SignRequest&)=delete;
 SignRequest& operator=(const SignRequest&)=delete;
 bool prepare(const uint8_t* data,uint32_t size){
  if(phase!=Phase::Empty||!digestInfo(data,size)){fail();return false;}
  digest.assign(data,data+size);phase=Phase::Pending;return true;
 }
 bool pending()const{return phase==Phase::Pending;}
 bool ready()const{return phase==Phase::Ready;}
 bool empty()const{return phase==Phase::Empty;}
 bool consumed()const{return phase==Phase::Consumed;}
 // Only the adapter that has checked the still-authenticated card context may
 // start another operation. Failed or incomplete requests can never restart.
 bool prepareNext(const uint8_t* data,uint32_t size){
  if(!consumed()){fail();return false;}
  phase=Phase::Empty;return prepare(data,size);
 }
 bool beginAuthentication(){
  if(!pending()){fail();return false;}
  phase=Phase::Authenticating;return true;
 }
 const std::vector<uint8_t>& input()const{return digest;}
 bool complete(const uint8_t* data,uint32_t size){
  if(phase!=Phase::Authenticating||!data||size!=256){fail();return false;}
  signature.assign(data,data+size);phase=Phase::Ready;return true;
 }
 bool take(const uint8_t* data,uint32_t size,std::vector<uint8_t>& result){
  result.clear();
  if(!ready()||!data||size!=digest.size()||!std::equal(digest.begin(),digest.end(),data)){fail();return false;}
  result=std::move(signature);digest.clear();phase=Phase::Consumed;return true;
 }
 void fail(){digest.clear();signature.clear();phase=Phase::Failed;}
};
// Authentication belongs to one OS session and one physical card context.
// No secret is retained. Losing that context is terminal, never a PIN retry.
class AuthenticatedSession {
 bool attempted=false,authenticated=false,failed=false;
public:
 bool beginAuthentication(){
  if(failed||attempted){fail();return false;}
  attempted=true;return true;
 }
 bool completeAuthentication(){
  if(failed||!attempted||authenticated){fail();return false;}
  authenticated=true;return true;
 }
 bool hasAttempted()const{return attempted;}
 bool isFailed()const{return failed;}
 bool reuse(bool validCard,bool sameContext){
  if(failed||!authenticated||!validCard||!sameContext){fail();return false;}
  return true;
 }
 void fail(){failed=true;authenticated=false;}
};
}
