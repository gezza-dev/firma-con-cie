// SPDX-License-Identifier: BSD-3-Clause
#include <windows.h>
#include <wincrypt.h>
#include <winscard.h>
#include <bcrypt.h>
#include "cardmod_compat.h"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
static unsigned checks=0;
static void check(bool value){++checks;if(!value)throw std::runtime_error("minidriver regression at check "+std::to_string(checks));}
static LPVOID WINAPI allocate(SIZE_T size){return malloc(size);}
static LPVOID WINAPI resize(LPVOID p,SIZE_T size){return realloc(p,size);}
static void WINAPI release(LPVOID p){free(p);}
int main(int argc,char** argv){try{
 if(argc!=2)return 2;HMODULE module=LoadLibraryA(argv[1]);check(module!=nullptr);
 auto acquire=reinterpret_cast<decltype(&CardAcquireContext)>(GetProcAddress(module,"CardAcquireContext"));check(acquire!=nullptr);
 check(acquire(nullptr,0)==SCARD_E_INVALID_PARAMETER);
 BYTE atr[]={0x3b,0};wchar_t cardName[]=L"CIE ID Flutter Prototype Web";CARD_DATA d{};d.dwVersion=6;d.pwszCardName=cardName;d.pbAtr=atr;d.cbAtr=sizeof(atr);d.hScard=1;d.hSCardCtx=1;
 d.pfnCspAlloc=allocate;d.pfnCspReAlloc=resize;d.pfnCspFree=release;
 check(acquire(&d,0)==ERROR_REVISION_MISMATCH);d.dwVersion=8;check(acquire(&d,0)==0);check(d.dwVersion==7);
 PBYTE bytes=nullptr;DWORD count=0;char cardid[]="cardid";
 check(d.pfnCardReadFile(&d,nullptr,cardid,0,&bytes,&count)==0);check(count==16);release(bytes);
 char mscp[]="mscp",cmap[]="cmapfile";check(d.pfnCardReadFile(&d,mscp,cmap,0,&bytes,&count)==0);check(count==sizeof(CONTAINER_MAP_RECORD));
 auto map=reinterpret_cast<PCONTAINER_MAP_RECORD>(bytes);check(map->wSigKeySizeBits==2048&&map->wKeyExchangeKeySizeBits==0);release(bytes);
 CARD_CAPABILITIES caps{};caps.dwVersion=CARD_CAPABILITIES_CURRENT_VERSION;check(d.pfnCardQueryCapabilities(&d,&caps)==0);check(!caps.fKeyGen);
 for(DWORD version:{0UL,1UL,2UL,0xffffffffUL}){
  CARD_CAPABILITIES c{};c.dwVersion=version;check(d.pfnCardQueryCapabilities(&d,&c)==0&&c.dwVersion==1);
  CARD_FREE_SPACE_INFO f{};f.dwVersion=version;check(d.pfnCardQueryFreeSpace(&d,0,&f)==0&&f.dwVersion==1&&f.dwMaxKeyContainers==1);
  CARD_KEY_SIZES k{};k.dwVersion=version;check(d.pfnCardQueryKeySizes(&d,AT_SIGNATURE,0,&k)==0&&k.dwVersion==1&&k.dwMaximumBitlen==2048);
  CARD_FILE_INFO file{};file.dwVersion=version;check(d.pfnCardGetFileInfo(&d,nullptr,cardid,&file)==0&&file.dwVersion==1&&file.cbFileSize==16);
  CONTAINER_INFO container{};container.dwVersion=version;check(d.pfnCardGetContainerInfo(&d,0,0,&container)==0&&container.dwVersion==1&&container.cbSigPublicKey>0);release(container.pbSigPublicKey);
 }
 check(d.pfnCardQueryCapabilities(&d,nullptr)==SCARD_E_INVALID_PARAMETER);
 CARD_KEY_SIZES wrongKey{};check(d.pfnCardQueryKeySizes(&d,AT_KEYEXCHANGE,0,&wrongKey)==SCARD_E_INVALID_PARAMETER);
 PIN_INFO pin{};check(d.pfnCardGetProperty(&d,CP_CARD_PIN_INFO,reinterpret_cast<PBYTE>(&pin),sizeof(pin),&count,ROLE_USER)==0);check(pin.PinCachePolicy.PinCachePolicyType==PinCacheTimed&&pin.PinCachePolicy.dwPinCachePolicyInfo==60&&pin.PinCachePolicy.dwVersion==PIN_CACHE_POLICY_CURRENT_VERSION);check(!pin.dwChangePermission&&!pin.dwUnblockPermission);
 check(d.pfnCardGetProperty(&d,CP_CARD_PIN_INFO,reinterpret_cast<PBYTE>(&pin),sizeof(pin),&count,ROLE_ADMIN)==SCARD_E_UNSUPPORTED_FEATURE);
 check(d.pfnCardUnblockPin(nullptr,nullptr,nullptr,0,nullptr,0,0,0)==SCARD_E_UNSUPPORTED_FEATURE);
 BYTE digest[32]{};BCRYPT_PKCS1_PADDING_INFO padding{BCRYPT_SHA256_ALGORITHM};CARD_SIGNING_INFO info{};info.dwVersion=CARD_SIGNING_INFO_CURRENT_VERSION;info.dwKeySpec=AT_SIGNATURE;info.dwSigningFlags=CARD_PADDING_INFO_PRESENT|CARD_BUFFER_SIZE_ONLY;info.dwPaddingType=CARD_PADDING_PKCS1;info.pPaddingInfo=&padding;info.pbData=digest;info.cbData=sizeof(digest);
 check(d.pfnCardSignData(&d,&info)==0&&info.cbSignedData==256&&!info.pbSignedData);
 CARD_SIGNING_INFO legacy=info;legacy.dwSigningFlags=CARD_BUFFER_SIZE_ONLY;legacy.aiHashAlg=CALG_SHA_256;legacy.pPaddingInfo=reinterpret_cast<void*>(1);check(d.pfnCardSignData(&d,&legacy)==0&&legacy.cbSignedData==256);
 info.dwSigningFlags|=CARD_PADDING_PKCS1;check(d.pfnCardSignData(&d,&info)==0&&info.cbSignedData==256);info.dwSigningFlags&=~CARD_PADDING_PKCS1;
 info.dwSigningFlags=CARD_PADDING_INFO_PRESENT;check(d.pfnCardSignData(&d,&info)==SCARD_W_SECURITY_VIOLATION);
 BYTE secret[]="12345678";check(d.pfnCardAuthenticateEx(&d,ROLE_ADMIN,0,secret,8,nullptr,nullptr,nullptr)==SCARD_E_INVALID_PARAMETER);
 check(d.pfnCardAuthenticateEx(&d,ROLE_USER,0,secret,8,nullptr,nullptr,nullptr)==0);
 check(d.pfnCardSignData(&d,&info)==0);check(info.cbSignedData==256&&info.pbSignedData[0]==255&&info.pbSignedData[255]==0);release(info.pbSignedData);
 legacy.dwSigningFlags=0;check(d.pfnCardSignData(&d,&legacy)==0&&legacy.cbSignedData==256);release(legacy.pbSignedData);
 info.dwSigningFlags|=CARD_PADDING_PKCS1;check(d.pfnCardSignData(&d,&info)==0&&info.cbSignedData==256);release(info.pbSignedData);info.dwSigningFlags&=~CARD_PADDING_PKCS1;
 padding.pszAlgId=BCRYPT_SHA1_ALGORITHM;check(d.pfnCardSignData(&d,&info)==SCARD_E_UNSUPPORTED_FEATURE);
 // Reproduce KSP PIN collection in a second context. Its public discovery
 // invalidates the first context's card selection; authentication must rebuild
 // that context, checking the provided PIN once rather than trusting old state.
 HMODULE fake=LoadLibraryA((std::string(argv[1]).substr(0,std::string(argv[1]).find_last_of("\\/"))+"/backend/cie_web.dll").c_str());check(fake!=nullptr);
 auto auths=reinterpret_cast<unsigned(*)()>(GetProcAddress(fake,"cie_web_fake_auths"));check(auths!=nullptr);
 auto signs=reinterpret_cast<unsigned(*)()>(GetProcAddress(fake,"cie_web_fake_signs"));check(signs!=nullptr);
 auto signInput=reinterpret_cast<uint32_t(*)(uint8_t*,uint32_t)>(GetProcAddress(fake,"cie_web_fake_sign_input"));check(signInput!=nullptr);
 // Firefox osclientcerts sends a complete DigestInfo to NCryptSignHash, with
 // PKCS1 padding and pszAlgId=NULL. The KSP can also forward it as aiHashAlg=0.
 // Accept only canonical SHA-2 encodings; forward the bytes exactly once.
 const auto encodedAuths=auths();
 BCRYPT_PKCS1_PADDING_INFO encodedPadding{nullptr};
 CARD_SIGNING_INFO encodedInfo=info;encodedInfo.pPaddingInfo=&encodedPadding;
 for(BYTE algorithm:{1,2,3}){
  const unsigned digestSize=algorithm==1?32:algorithm==2?48:64;
  std::vector<BYTE> encoded={0x30,0,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,algorithm,5,0,4,0};
  encoded[1]=static_cast<BYTE>(17+digestSize);encoded[18]=static_cast<BYTE>(digestSize);
  encoded.resize(19+digestSize,0x5a);encodedInfo.pbData=encoded.data();encodedInfo.cbData=static_cast<DWORD>(encoded.size());
  for(unsigned form=0;form<3;++form){
   encodedInfo.dwVersion=form==2?CARD_SIGNING_INFO_BASIC_VERSION:CARD_SIGNING_INFO_CURRENT_VERSION;
   encodedInfo.dwSigningFlags=form==0?CARD_PADDING_INFO_PRESENT:0;
   encodedInfo.aiHashAlg=0;
   const auto beforeSigns=signs();
   encodedInfo.dwSigningFlags|=CARD_BUFFER_SIZE_ONLY;
   check(d.pfnCardSignData(&d,&encodedInfo)==0&&encodedInfo.cbSignedData==256&&!encodedInfo.pbSignedData&&signs()==beforeSigns);
   encodedInfo.dwSigningFlags&=~CARD_BUFFER_SIZE_ONLY;
   check(d.pfnCardSignData(&d,&encodedInfo)==0&&encodedInfo.cbSignedData==256&&signs()==beforeSigns+1);
   BYTE forwarded[83]{};check(signInput(forwarded,sizeof(forwarded))==encoded.size()&&!memcmp(forwarded,encoded.data(),encoded.size()));
   check(encodedInfo.pbSignedData[0]==255&&encodedInfo.pbSignedData[255]==0);release(encodedInfo.pbSignedData);
  }
 }
 encodedInfo.dwVersion=CARD_SIGNING_INFO_CURRENT_VERSION;encodedInfo.dwSigningFlags=CARD_PADDING_INFO_PRESENT;
 const auto beforeInvalid=signs();
 // Raw hashes/blocks, missing input, wrong OID, BER, trailing data and PSS
 // cannot bypass the provider's restricted client-authentication contract.
 std::vector<BYTE> canonical={0x30,0x31,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,1,5,0,4,0x20};canonical.resize(51,0x5a);
 auto rejects=[&](std::vector<BYTE> data){encodedInfo.pbData=data.data();encodedInfo.cbData=static_cast<DWORD>(data.size());check(d.pfnCardSignData(&d,&encodedInfo)==SCARD_E_UNSUPPORTED_FEATURE&&signs()==beforeInvalid&&!encodedInfo.pbSignedData);};
 rejects(std::vector<BYTE>(32,0));rejects(std::vector<BYTE>(256,0));rejects({});
 for(unsigned offset:{1,8,14,16,18}){auto malformed=canonical;malformed[offset]^=0x01;rejects(malformed);}
 auto trailing=canonical;trailing.push_back(0);rejects(trailing);
 encodedInfo.pbData=canonical.data();encodedInfo.cbData=static_cast<DWORD>(canonical.size());encodedInfo.dwPaddingType=CARD_PADDING_PSS;
 check(d.pfnCardSignData(&d,&encodedInfo)==SCARD_E_UNSUPPORTED_FEATURE&&signs()==beforeInvalid);
 check(auths()==encodedAuths);
 // Advertising PSS would make browsers select a signing operation the IAS
 // authentication key cannot currently perform. Test actual PSS parameters,
 // including size queries, and ensure rejection leaves PKCS1 usable.
 DWORD supportedPadding=0;
 check(d.pfnCardGetProperty(&d,CP_PADDING_SCHEMES,reinterpret_cast<PBYTE>(&supportedPadding),sizeof(supportedPadding),&count,CARD_ASYMMETRIC_OPERATION)==0);
 check(count==sizeof(supportedPadding)&&supportedPadding==CARD_PADDING_PKCS1);
 BYTE pssDigest[64]{};
 for(LPCWSTR hash:{BCRYPT_SHA256_ALGORITHM,BCRYPT_SHA384_ALGORITHM,BCRYPT_SHA512_ALGORITHM}){
  const DWORD n=!wcscmp(hash,BCRYPT_SHA256_ALGORITHM)?32:!wcscmp(hash,BCRYPT_SHA384_ALGORITHM)?48:64;
  BCRYPT_PSS_PADDING_INFO pssPadding{hash,n};
  CARD_SIGNING_INFO pss{};pss.dwVersion=CARD_SIGNING_INFO_CURRENT_VERSION;pss.dwKeySpec=AT_SIGNATURE;
  pss.dwPaddingType=CARD_PADDING_PSS;pss.pPaddingInfo=&pssPadding;pss.pbData=pssDigest;pss.cbData=n;
  for(DWORD flags:{CARD_PADDING_INFO_PRESENT,CARD_PADDING_INFO_PRESENT|CARD_BUFFER_SIZE_ONLY}){
   pss.dwSigningFlags=flags;
   check(d.pfnCardSignData(&d,&pss)==SCARD_E_UNSUPPORTED_FEATURE&&!pss.pbSignedData&&!pss.cbSignedData&&signs()==beforeInvalid&&auths()==encodedAuths);
  }
 }
 padding.pszAlgId=BCRYPT_SHA256_ALGORITHM;
 check(d.pfnCardSignData(&d,&info)==0&&info.cbSignedData==256&&signs()==beforeInvalid+1&&auths()==encodedAuths);release(info.pbSignedData);
 // Browser login accepts only eight decimal digits, for both entry points.
 // Reject locally without authenticating the card or consuming PIN attempts.
 auto authCount=auths();BYTE partial[]="5678",nonNumeric[]="1234567x",longPin[]="123456789";DWORD invalidAttempts=0;
 check(d.pfnCardAuthenticateEx(&d,ROLE_USER,0,partial,4,nullptr,nullptr,&invalidAttempts)==SCARD_E_INVALID_PARAMETER&&auths()==authCount&&invalidAttempts==DWORD(-1));
 check(d.pfnCardAuthenticatePin(&d,const_cast<LPWSTR>(L"user"),partial,4,&invalidAttempts)==SCARD_E_INVALID_PARAMETER&&auths()==authCount);
 check(d.pfnCardAuthenticateEx(&d,ROLE_USER,0,nonNumeric,8,nullptr,nullptr,nullptr)==SCARD_E_INVALID_PARAMETER&&auths()==authCount);
 check(d.pfnCardAuthenticateEx(&d,ROLE_USER,0,longPin,9,nullptr,nullptr,nullptr)==SCARD_E_INVALID_PARAMETER&&auths()==authCount);
 CARD_DATA other=d;other.pvVendorSpecific=nullptr;check(acquire(&other,0)==0);
 PIN_INFO otherPin{};check(other.pfnCardGetProperty(&other,CP_CARD_PIN_INFO,reinterpret_cast<PBYTE>(&otherPin),sizeof(otherPin),&count,ROLE_USER)==0&&otherPin.PinCachePolicy.PinCachePolicyType==PinCacheTimed&&otherPin.PinCachePolicy.dwPinCachePolicyInfo==60);
 auto before=auths();check(d.pfnCardAuthenticateEx(&d,ROLE_USER,0,secret,8,nullptr,nullptr,nullptr)==0&&auths()==before+1);
 padding.pszAlgId=BCRYPT_SHA256_ALGORITHM;check(d.pfnCardSignData(&d,&info)==0);release(info.pbSignedData);
 // A repeated explicit callback must verify its input even after success.
 BYTE wrong[]="87654321";before=auths();DWORD attempts=0;
 check(d.pfnCardAuthenticateEx(&d,ROLE_USER,0,wrong,8,nullptr,nullptr,&attempts)==SCARD_W_WRONG_CHV&&attempts==2&&auths()==before+1);
 check(d.pfnCardSignData(&d,&info)==SCARD_W_SECURITY_VIOLATION);
 check(d.pfnCardDeleteContext(&other)==0);FreeLibrary(fake);
 check(d.pfnCardDeleteContext(&d)==0&&d.pvVendorSpecific==nullptr);check(d.pfnCardDeleteContext(&d)==0);FreeLibrary(module);
 std::cout<<checks<<" isolated minidriver checks passed\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
