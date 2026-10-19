// SPDX-License-Identifier: BSD-3-Clause
// Read-only discovery probe: no PIN argument, no VERIFY, no output certificate.
#include "cie_web.h"
#ifdef __APPLE__
#include <PCSC/winscard.h>
#include <PCSC/pcsclite.h>
using DWORD=uint32_t;
#define SCardListReadersA SCardListReaders
#define SCardConnectA SCardConnect
#define SCardStatusA SCardStatus
#else
#include <winscard.h>
#include <scarderr.h>
#include <winsmcrd.h>
#endif
#include <iostream>
#include <vector>
static int32_t send(void* context,const uint8_t* request,uint32_t size,uint8_t* response,uint32_t* length){
 auto card=*static_cast<SCARDHANDLE*>(context);DWORD n=*length;
 auto status=SCardTransmit(card,SCARD_PCI_T1,request,size,nullptr,response,&n);*length=n;return status?CIE_WEB_TRANSPORT:0;
}
int main(){
 SCARDCONTEXT context=0;if(SCardEstablishContext(SCARD_SCOPE_USER,nullptr,nullptr,&context)!=SCARD_S_SUCCESS){std::cout<<"{\"status\":\"pcsc_unavailable\"}\n";return 2;}
 struct Release{SCARDCONTEXT c;~Release(){SCardReleaseContext(c);}} release{context};
 DWORD size=0;auto status=SCardListReadersA(context,nullptr,nullptr,&size);
 if(status||size<2){std::cout<<"{\"status\":\"no_reader\"}\n";return 3;}
 std::vector<char> readers(size);if(SCardListReadersA(context,nullptr,readers.data(),&size))return 2;
 SCARDHANDLE card=0;DWORD protocol=0;
 if(SCardConnectA(context,readers.data(),SCARD_SHARE_SHARED,SCARD_PROTOCOL_T1,&card,&protocol)){std::cout<<"{\"status\":\"no_card\"}\n";return 4;}
 struct Close{SCARDHANDLE c;bool locked=false;~Close(){if(locked)SCardEndTransaction(c,SCARD_RESET_CARD);SCardDisconnect(c,SCARD_LEAVE_CARD);}} close{card};
 if(SCardBeginTransaction(card))return 5;close.locked=true;
 uint8_t atr[64];DWORD length=sizeof(atr),state=0,nameSize=4096;char name[4096];if(SCardStatusA(card,name,&nameSize,&state,&protocol,atr,&length))return 6;
 CieWebSession* session=nullptr;auto opened=cie_web_open(atr,length,send,&card,nullptr,&session);
 if(opened){std::cout<<"{\"status\":\"open_failed\",\"code\":"<<opened<<"}\n";return 7;}
 struct Free{CieWebSession* s;~Free(){cie_web_close(s);}} free{session};
 uint32_t bytes=0;auto certificate=cie_web_certificate(session,nullptr,&bytes);
 std::cout<<"{\"status\":\"discovery_complete\",\"certificateCode\":"<<certificate<<",\"certificateBytes\":"<<bytes<<",\"pinSent\":false}\n";
 return certificate?8:0;
}
