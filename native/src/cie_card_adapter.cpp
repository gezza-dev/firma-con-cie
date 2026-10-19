// SPDX-License-Identifier: BSD-3-Clause
// Thin adapter to the existing IAS and signing SDK implementation. No cache,
// enrollment, saved PIN fragments or platform keychain changes are performed.
#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
#include "cie_bridge.h"
#include "middleware_abi.h"
#include "pin_operations.h"
#include "card_identification.h"
#include "pdf_appearance.h"
#include "pairing_sod.h"
#include "card_material.h"
#include "cie_enrollment_types.h"
#include "Native/CardholderName.h"
#include "cie-pkcs11/Crypto/sha256.h"
#include "cie-pkcs11/Crypto/ASNParser.h"
#include "cie-pkcs11/Crypto/sha512.h"
extern "C" int cie_document_p7m_info(const char*,uint32_t*);
extern "C" int cie_document_pdf_info(const char*,int,CiePdfPageInfo*);
extern "C" int cie_document_prepare_appearance(const char*,const CiePdfAppearance*,CiePdfAppearance*);
#include "cie-pkcs11/CSP/AbilitaCIE.h"
#include "cie-pkcs11/CSP/ATR.h"
#include "cie-pkcs11/CSP/IAS.h"
#include "cie-pkcs11/Sign/CIEVerify.h"
#include "disigonsdk.h"
#undef min
static_assert(sizeof(CieVerifyInfo) == sizeof(verifyInfo_t));
static_assert(offsetof(CieVerifyInfo, isSignValid) == offsetof(verifyInfo_t, isSignValid));

namespace {
// PIN/PUK operations must not inherit the legacy reconnect-and-retransmit
// callback. Preserve exclusive access on explicit reset; transmit every APDU once.
int pinTransmit(safeConnection* connection,uint8_t* apdu,DWORD size,uint8_t* response,DWORD* capacity) {
    if(!connection || !apdu || !response || !capacity) return SCARD_E_INVALID_PARAMETER;
    if(size==2) {
        uint16_t command=0;std::memcpy(&command,apdu,2);
        if(command==0xfffd) {
            if(*capacity<sizeof(connection->hCard)+2) return SCARD_E_INSUFFICIENT_BUFFER;
            std::memcpy(response,&connection->hCard,sizeof(connection->hCard));
            response[sizeof(connection->hCard)]=response[sizeof(connection->hCard)+1]=0;
            *capacity=sizeof(connection->hCard)+2;return SCARD_S_SUCCESS;
        }
        if(command==0xffff || command==0xfffe) {
            if(*capacity<2) return SCARD_E_INSUFFICIENT_BUFFER;
            DWORD protocol=0;
            auto status=SCardReconnect(connection->hCard,SCARD_SHARE_EXCLUSIVE,SCARD_PROTOCOL_T1,
                command==0xfffe ? SCARD_UNPOWER_CARD : SCARD_RESET_CARD,&protocol);
            if(status==SCARD_S_SUCCESS) {response[0]=0x90;response[1]=0;*capacity=2;}
            return status;
        }
        return SCARD_E_INVALID_PARAMETER;
    }
    return SCardTransmit(connection->hCard,SCARD_PCI_T1,apdu,size,nullptr,response,capacity);
}
// Shared connections coexist with system smart-card handles; a PC/SC
// transaction serializes every actual command. Reconnect only for initial reset.
struct SessionConnection : safeConnection {
 bool managed=false,locked=false;
 SessionConnection(SCARDCONTEXT c,const char* r,DWORD mode):safeConnection(c,r,mode){}
 ~SessionConnection(){
  if(managed && hCard){
   if(locked)SCardEndTransaction(hCard,SCARD_RESET_CARD);
   SCardDisconnect(hCard,SCARD_LEAVE_CARD);hCard=0;
  }
 }
};
int pairingTransmit(SessionConnection* connection,uint8_t* apdu,DWORD size,uint8_t* response,DWORD* capacity){
 if(!connection||!apdu||!response||!capacity)return SCARD_E_INVALID_PARAMETER;
 if(size==2){uint16_t command=0;std::memcpy(&command,apdu,2);
  if(command==0xfffd)return pinTransmit(connection,apdu,size,response,capacity);
  if(command!=0xffff||connection->locked||*capacity<2)return SCARD_E_INVALID_PARAMETER;
  DWORD protocol=0;auto status=SCardReconnect(connection->hCard,SCARD_SHARE_SHARED,SCARD_PROTOCOL_T1,SCARD_RESET_CARD,&protocol);
  if(status!=SCARD_S_SUCCESS)return status;
  status=SCardBeginTransaction(connection->hCard);if(status!=SCARD_S_SUCCESS)return status;
  connection->locked=true;response[0]=0x90;response[1]=0;*capacity=2;return SCARD_S_SUCCESS;
 }
 if(!connection->locked)return SCARD_E_INVALID_PARAMETER;
 return SCardTransmit(connection->hCard,SCARD_PCI_T1,apdu,size,nullptr,response,capacity);
}
struct Context {
    SCARDCONTEXT value = 0;
    Context() {
        if (SCardEstablishContext(SCARD_SCOPE_USER, nullptr, nullptr, &value) != SCARD_S_SUCCESS)
            throw std::runtime_error("Servizio smart card non disponibile");
    }
    ~Context() { if (value) SCardReleaseContext(value); }
};
// Public identification owns a separate transaction. Never reset the card on
// entry or exit; the full Card session below remains reserved for authentication.
struct IdentificationConnection {
    SCARDHANDLE handle = 0;
    bool locked = false, exclusive = false;
    cie_identification::ReadCommands commands;
    IdentificationConnection() = default;
    IdentificationConnection(const IdentificationConnection&) = delete;
    IdentificationConnection& operator=(const IdentificationConnection&) = delete;
    ~IdentificationConnection() {
        if (handle) {
            if (locked && !exclusive) SCardEndTransaction(handle, SCARD_LEAVE_CARD);
            SCardDisconnect(handle, SCARD_LEAVE_CARD);
        }
    }
};
int identificationTransmit(IdentificationConnection* connection, uint8_t* apdu,
    DWORD size, uint8_t* response, DWORD* capacity) {
    if (!connection || !connection->handle || !connection->locked || !response || !capacity ||
        !connection->commands.accept(apdu, size)) return SCARD_E_INVALID_PARAMETER;
    // A reset/removed-card error ends this attempt; never reconnect or replay.
    return SCardTransmit(connection->handle, SCARD_PCI_T1, apdu, size, nullptr, response, capacity);
}
std::string identify(const char* reader, bool idleOnly=false) {
    Context context;
    IdentificationConnection connection;
    DWORD protocol = 0;
    if (SCardConnect(context.value, reader, idleOnly ? SCARD_SHARE_EXCLUSIVE : SCARD_SHARE_SHARED, SCARD_PROTOCOL_T1,
        &connection.handle, &protocol) != SCARD_S_SUCCESS)
        throw std::runtime_error("Carta non disponibile sul lettore selezionato");
    if (!idleOnly && SCardBeginTransaction(connection.handle) != SCARD_S_SUCCESS)
        throw std::runtime_error("Carta occupata o non disponibile");
    connection.locked = true;
    connection.exclusive = idleOnly;
    uint8_t bytes[64] = {};
    DWORD size = sizeof(bytes);
    if (SCardGetAttrib(connection.handle, SCARD_ATTR_ATR_STRING, bytes, &size) != SCARD_S_SUCCESS ||
        !size || size > sizeof(bytes) ||
        get_type(std::vector<uint8_t>(bytes, bytes + size)) == CIE_Type::CIE_Unknown)
        throw std::runtime_error("Carta CIE non riconosciuta");
    ByteArray atr(bytes, size);
    IAS ias(reinterpret_cast<CToken::TokenTransmitCallback>(identificationTransmit), atr);
    ias.SetCardContext(&connection);
    return cie_identification::readIdentifier<IAS, ByteDynArray>(ias);
}
struct Card {
    Context context;
    SessionConnection connection;
    ByteDynArray atr;
    std::unique_ptr<IAS> ias;
    std::string id;
    explicit Card(const char* reader, bool exclusive=false,int* phase=nullptr,bool transactional=false) : connection(context.value, reader, exclusive ? SCARD_SHARE_EXCLUSIVE : SCARD_SHARE_SHARED) {
        connection.managed=transactional;
        auto stage=[&](int value){if(phase)*phase=value;};
        stage(-51);
        if (!connection.hCard) throw std::runtime_error("Carta non disponibile sul lettore selezionato");
        stage(-52);
        uint8_t data[64] = {};
        DWORD size = sizeof(data);
        if (SCardGetAttrib(connection.hCard, SCARD_ATTR_ATR_STRING, data, &size) != SCARD_S_SUCCESS || size > sizeof(data))
            throw std::runtime_error("Impossibile leggere ATR");
        atr = ByteArray(data, size);
        stage(-53);
        ias = std::make_unique<IAS>(reinterpret_cast<CToken::TokenTransmitCallback>(transactional ? reinterpret_cast<CToken::TokenTransmitCallback>(pairingTransmit) : reinterpret_cast<CToken::TokenTransmitCallback>(exclusive ? pinTransmit : TokenTransmitCallback)), atr);
        ias->SetCardContext(&connection);
        stage(-54);ias->token.Reset();if(transactional&&!connection.locked)throw std::runtime_error("Transaction unavailable");
        stage(-55);ias->SelectAID_IAS();
        stage(-56);ias->ReadPAN();
        stage(-57);ias->SelectAID_CIE();
        ByteDynArray services;
        stage(-58);ias->ReadIdServizi(services);
        id.assign(reinterpret_cast<const char*>(services.data()), services.size());
        while (!id.empty() && id.back() == '\0') id.pop_back();
        if (id.empty() || id.size() >= 64) throw std::runtime_error("Identificativo CIE non valido");
    }
    void secure() {
        ByteDynArray response;
        ias->attemptsRemaining=-1;
        ias->InitEncKey();ias->ReadDappPubKey(response);
        ias->InitDHParam();ias->InitExtAuthKeyParam();
        ias->DHKeyExchange();ias->DAPP();
    }
    int verify(bool unblock,char* secret) {
        ByteArray bytes(reinterpret_cast<BYTE*>(secret),8);
        return unblock ? ias->VerifyPUK(bytes) : ias->VerifyPIN(bytes);
    }
    int replace(bool unblock,char* old,char* replacement) {
        ByteArray current(reinterpret_cast<BYTE*>(old),8),next(reinterpret_cast<BYTE*>(replacement),8);
        return unblock ? ias->ChangePIN(next) : ias->ChangePIN(current,next);
    }
};
}

// No reader enumeration, enrollment/cache access or automatic retry. Identity is
// checked on the exclusively connected card before any PIN/PUK is transmitted.
static int64_t updatePin(const char* reader,const char* expected,char* authentication,char* replacement,int* phase,bool unblock) {
    cie_pin::Secrets secrets{authentication,replacement};
    if(!phase) return -1;
    *phase=0;
    if(!reader || !*reader || !expected || !*expected || !cie_pin::digits(authentication) ||
       !cie_pin::newPin(replacement)) return -1;
    try { Card card(reader,true);return cie_pin::update(card,unblock,expected,authentication,replacement,*phase); }
    catch(...) { return -2; }
}
extern "C" CIE_EXPORT int64_t cie_card_change_pin(const char* reader,const char* expected,char* current,char* replacement,int* phase) {
    return updatePin(reader,expected,current,replacement,phase,false);
}
extern "C" CIE_EXPORT int64_t cie_card_unblock_pin(const char* reader,const char* expected,char* puk,char* replacement,int* phase) {
    return updatePin(reader,expected,puk,replacement,phase,true);
}

namespace {
using cie_pairing::PairMaterial;
}
// Read-only diagnostic preparation. There is no VERIFY or PIN input on this path.
extern "C" CIE_EXPORT int64_t cie_card_pair_preflight(const char* reader,const char* expected){
 int phase=-29;
 try{if(!reader||!expected||!*reader||!*expected)return -1;Card card(reader,false,&phase,true);if(card.id!=expected)return -10;PairMaterial material;material.prepare(card,phase);return 0;}
 catch(...){return phase;}
}
// Authentication only: no PIN mutation, cache writes, reconnect or replay.
extern "C" CIE_EXPORT int64_t cie_card_pair_authenticate(const char* reader,const char* expected,char* pin) {
 cie_pin::Secrets secrets{pin,nullptr};
 if(!reader||!*reader||!expected||!*expected||!cie_pin::digits(pin))return -1;
 int phase=-29;
 try{Card card(reader,false,&phase,true);if(card.id!=expected)return -10;PairMaterial material;material.prepare(card,phase);
  phase=-40;auto status=card.verify(false,pin);if(status!=0x9000)return status;
  material.verifySod(card,phase);return 0;
 }catch(...){return phase;}
}
// Explicit public certificate provisioning for OS web-authentication adapters.
// One authentication, strict SOD verification, no prefix storage or PIN change.
extern "C" CIE_EXPORT int64_t cie_card_web_enroll(const char* reader,const char* expected,char* pin,uint8_t* output,uint32_t* length){
 cie_pin::Secrets secrets{pin,nullptr};
 if(!reader||!*reader||!expected||!*expected||!cie_pin::digits(pin)||!output||!length||*length<8192)return -1;
 *length=0;int phase=-29;
 try{Card card(reader,false,&phase,true);if(card.id!=expected)return -10;
  PairMaterial material;material.prepare(card,phase);phase=-40;auto status=card.verify(false,pin);if(status!=0x9000)return status;
  material.verifySod(card,phase);auto& cert=material.certificate;auto size=GetASN1DataLenght(cert);
  if(!size||size>8192||size>cert.size())return -42;std::memcpy(output,cert.data(),size);*length=size;return 0;
 }catch(...){return phase;}
}

// A single VERIFY produces the prefix-independent public enrollment material.
// Copy exactly the certificate whose DG was checked against the signed SOD.
extern "C" CIE_EXPORT int64_t cie_card_enroll_v2(const char* reader,const char* expected,char* pin,CieEnrollmentMaterial* output){
 cie_pin::Secrets secrets{pin,nullptr};
 if(!output||output->size!=sizeof(*output)||!reader||!*reader||!expected||!*expected||!cie_pin::digits(pin))return -1;
 output->version=0;output->certificateLength=0;output->fullName[0]=0;int phase=-29;
 try{Card card(reader,false,&phase,true);if(card.id!=expected)return -10;
  PairMaterial material;material.prepare(card,phase);phase=-40;auto status=card.verify(false,pin);if(status!=0x9000)return status;
  material.verifySod(card,phase);
  std::string verifiedId(reinterpret_cast<const char*>(material.services.data()),material.services.size());
  while(!verifiedId.empty()&&verifiedId.back()=='\0')verifiedId.pop_back();if(verifiedId!=expected)return -10;
  auto& cert=material.certificate;auto length=GetASN1DataLenght(cert);
  if(!length||length>sizeof(output->certificate)||length>cert.size())return -42;
  phase=-45;auto name=cie::cardholderName(cert.data(),length);if(name.size()>=sizeof(output->fullName))return phase;
  std::memcpy(output->certificate,cert.data(),length);std::memcpy(output->fullName,name.c_str(),name.size()+1);
  output->certificateLength=length;output->version=2;return 0;
 }catch(...){return phase;}
}
// Automatic discovery never waits for another client's transaction, resets the
// card, or shares a connection with Safari/CTK/KSP. Busy readers are deferred.
extern "C" CIE_EXPORT int cie_card_identify_idle(const char* reader,char* card,size_t capacity){
 try{if(!reader||!*reader||!card||capacity<64)return -1;auto id=identify(reader,true);std::memcpy(card,id.c_str(),id.size()+1);return 0;}
 catch(const std::exception& error){return std::string(error.what())=="Carta CIE non riconosciuta"?-4:-3;}
 catch(...){return -3;}
}

extern "C" CIE_EXPORT int cie_card_identify(const char* reader, char* card, size_t capacity) {
    try {
        if (!reader || !*reader || !card || capacity < 64) return -1;
        const auto id = identify(reader);
        std::memcpy(card, id.c_str(), id.size() + 1);
        return 0;
    } catch (...) { return -2; }
}
static int64_t signCard(const char* reader, const char* expected,
    const char* input, const char* output, const char* format, char* pin,const CiePdfAppearance* appearance) {
    try {
        if (!reader || !expected || !input || !output || !format || !pin || std::strlen(pin) != 8) return -1;
        CiePdfAppearance raw{};
        if (appearance && (std::strcmp(format,"pdf") || cie_document_prepare_appearance(input,appearance,&raw))) return -20;
        if(!appearance && !std::strcmp(format,"pdf")) {CiePdfPageInfo info{};info.size=sizeof(info);if(cie_document_pdf_info(input,0,&info))return -21;}
        if(!std::strcmp(format,"cosign")){uint32_t count=0;if(cie_document_p7m_info(input,&count))return -22;}
        Card card(reader,false,nullptr,true);
        if (card.id != expected) return -10;
        // Same SDK path as CIESign::sign, retaining its full long error value.
        // IAS receives the complete PIN, so no middleware enrollment/cache is used.
        std::unique_ptr<void, decltype(&disigon_sign_cleanup)> ctx(disigon_sign_init(), disigon_sign_cleanup);
        if (!ctx) return -3;
        auto set = [&](int option, void* value) {
            long status = disigon_sign_set(ctx.get(), option, value);
            if (status) throw status;
        };
        set(DISIGON_OPT_IAS_INSTANCE, card.ias.get());
        set(DISIGON_OPT_CADES, reinterpret_cast<void*>(1));
        set(DISIGON_OPT_PIN, pin);
        set(DISIGON_OPT_INPUTFILE, const_cast<char*>(input));
        set(DISIGON_OPT_OUTPUTFILE, const_cast<char*>(output));
        if (std::strcmp(format, "pdf") == 0) {
            long page = appearance ? raw.page : 0;
            float left=appearance ? raw.left : 0, bottom=appearance ? raw.top+raw.height : 0;
            float width=appearance ? raw.width : 0,height=appearance ? raw.height : 0;
            set(DISIGON_OPT_PDF_SUBFILTER, const_cast<char*>(DISIGON_PDF_SUBFILTER_ETSI_CADES));
            set(DISIGON_OPT_PDF_PAGE, &page);
            set(DISIGON_OPT_PDF_LEFT, &left);
            set(DISIGON_OPT_PDF_BOTTOM, &bottom);
            set(DISIGON_OPT_PDF_WIDTH, &width);
            set(DISIGON_OPT_PDF_HEIGHT, &height);
            if(appearance) set(DISIGON_OPT_PDF_IMAGEPATH,const_cast<char*>(appearance->imagePath));
            set(DISIGON_OPT_INPUTFILE_TYPE, reinterpret_cast<void*>(DISIGON_FILETYPE_PDF));
        } else {
            set(DISIGON_OPT_INPUTFILE_TYPE, reinterpret_cast<void*>(!std::strcmp(format,"cosign") ? DISIGON_FILETYPE_P7M : DISIGON_FILETYPE_PLAINTEXT));
            set(DISIGON_OPT_DETACHED, nullptr);
        }
        set(DISIGON_OPT_VERIFY_USER_CERTIFICATE, nullptr);
        return disigon_sign_sign(ctx.get());
    } catch (long error) { return error; }
    catch (...) { return -2; }
}

extern "C" CIE_EXPORT int64_t cie_card_sign(const char* r,const char* c,const char* i,const char* o,const char* f,char* p) { return signCard(r,c,i,o,f,p,nullptr); }
extern "C" CIE_EXPORT int64_t cie_card_sign_pdf(const char* r,const char* c,const char* i,const char* o,char* p,const CiePdfAppearance* a) { return a ? signCard(r,c,i,o,"pdf",p,a) : -20; }
