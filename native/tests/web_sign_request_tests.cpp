// SPDX-License-Identifier: BSD-3-Clause
#include "web_sign_request.h"
#include <iostream>
#include <stdexcept>
static unsigned checks=0;
static void check(bool ok){++checks;if(!ok)throw std::runtime_error("OS sign request binding regression");}
int main(){
 for(unsigned algorithm=1;algorithm<=3;++algorithm){
  const auto n=algorithm==1?32:algorithm==2?48:64;
  std::vector<uint8_t> input={0x30,static_cast<uint8_t>(17+n),0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,static_cast<uint8_t>(algorithm),0x05,0,0x04,static_cast<uint8_t>(n)};
  input.resize(19+n,0xaa);std::vector<uint8_t> signature(256,0x55),out;
  cie_web::SignRequest r;check(r.empty());check(r.prepare(input.data(),input.size()));check(r.pending());
  check(r.beginAuthentication());check(r.input()==input);check(r.complete(signature.data(),signature.size()));
  check(r.ready());check(r.take(input.data(),input.size(),out));check(out==signature);
  check(!r.take(input.data(),input.size(),out));check(out.empty());check(!r.beginAuthentication());
  cie_web::SignRequest mismatch;check(mismatch.prepare(input.data(),input.size()));check(mismatch.beginAuthentication());check(mismatch.complete(signature.data(),256));
  auto changed=input;changed.back()^=1;check(!mismatch.take(changed.data(),changed.size(),out));check(out.empty());check(!mismatch.ready());check(!mismatch.take(input.data(),input.size(),out));
  cie_web::SignRequest overwritten;check(overwritten.prepare(input.data(),input.size()));check(!overwritten.prepare(changed.data(),changed.size()));check(!overwritten.beginAuthentication());
  cie_web::SignRequest repeated;check(repeated.prepare(input.data(),input.size()));check(repeated.beginAuthentication());check(!repeated.beginAuthentication());check(!repeated.complete(signature.data(),256));
  cie_web::SignRequest failed;check(failed.prepare(input.data(),input.size()));check(failed.beginAuthentication());failed.fail();check(!failed.complete(signature.data(),256));check(!failed.take(input.data(),input.size(),out));
  cie_web::SignRequest shortResult;check(shortResult.prepare(input.data(),input.size()));check(shortResult.beginAuthentication());check(!shortResult.complete(signature.data(),255));check(!shortResult.take(input.data(),input.size(),out));
  cie_web::SignRequest premature;check(!premature.complete(signature.data(),256));check(!premature.prepare(input.data(),input.size()));
 }
 // Simulate Safari's repeated beginAuth/signData calls in one OS session.
 // A successful VERIFY occurs once; later operations require the same live
 // context and compute fresh signatures, never replaying a previous result.
 for(unsigned loss=0;loss<4;++loss){
  cie_web::AuthenticatedSession auth;cie_web::SignRequest request;
  unsigned verifyCalls=0,signCalls=0;
  std::vector<uint8_t> input={0x30,0x31,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,1,0x05,0,0x04,32};
  input.resize(51,0x22);std::vector<uint8_t> signature(256,0x44),out;
  check(request.prepare(input.data(),input.size()));check(request.beginAuthentication());
  check(auth.beginAuthentication());++verifyCalls;check(auth.completeAuthentication());
  ++signCalls;check(request.complete(signature.data(),256));check(request.take(input.data(),input.size(),out));
  for(unsigned next=0;next<5;++next){
   check(auth.reuse(true,true)); // preemptive beginAuth, no PIN operation
   check(auth.reuse(true,true)); // checked again inside signing transaction
   input.back()++;check(request.prepareNext(input.data(),input.size()));
   check(request.beginAuthentication());++signCalls;
   signature.back()++;check(request.complete(signature.data(),256));
   check(request.take(input.data(),input.size(),out));check(out==signature);
  }
  check(verifyCalls==1);check(signCalls==6);
  if(loss==0)check(!auth.reuse(false,true)); // card removed
  if(loss==1)check(!auth.reuse(true,false)); // reset or foreign owner
  if(loss==2){auth.fail();check(!auth.reuse(true,true));} // transport/sign failure
  if(loss==3)check(!auth.beginAuthentication()); // duplicate VERIFY blocked
  check(auth.isFailed());check(!auth.reuse(true,true));check(!auth.beginAuthentication());
  request.fail();check(!request.prepareNext(input.data(),input.size()));
 }
 cie_web::AuthenticatedSession wrongPIN;
 check(wrongPIN.beginAuthentication());wrongPIN.fail();
 check(!wrongPIN.beginAuthentication());check(!wrongPIN.completeAuthentication());check(!wrongPIN.reuse(true,true));
 cie_web::AuthenticatedSession neverAuthenticated;check(!neverAuthenticated.reuse(true,true));
 cie_web::SignRequest incomplete;std::vector<uint8_t> dummy(51);check(!incomplete.prepareNext(dummy.data(),dummy.size()));
 cie_web::SignRequest invalid;check(!invalid.prepare(nullptr,51));check(!invalid.pending());
 std::cout<<checks<<" OS sign request binding checks passed\n";
}
