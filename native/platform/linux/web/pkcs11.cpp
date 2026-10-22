// SPDX-License-Identifier: BSD-3-Clause
// Derived from RSA Security Inc. PKCS #11 Cryptographic Token Interface
// (Cryptoki) declarations. Read-only RSA client-authentication token for NSS.
#include "card.h"
#include "exports.h"
#include "web_policy.h"
#include <openssl/x509.h>
#include <openssl/core_names.h>
#include <openssl/rand.h>
#include <openssl/rsa.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <cstdio>
#include <ctime>
#include <deque>
#include <map>
#include <mutex>
#include <thread>
#ifdef _WIN32
#include <process.h>
#define getpid _getpid
#undef CreateMutex
#define CIE_GET_FUNCTION_LIST CieGetFunctionList
#else
#include <unistd.h>
#define CIE_GET_FUNCTION_LIST C_GetFunctionList
#endif

namespace {
using Bytes = std::vector<uint8_t>;
using Clock = std::chrono::steady_clock;
constexpr auto idleLimit = std::chrono::seconds(30);
constexpr CK_OBJECT_HANDLE certificateObject=1, publicObject=2, privateObject=3;
constexpr CK_MECHANISM_TYPE mechanisms[]={CKM_RSA_PKCS,CKM_SHA256_RSA_PKCS,CKM_SHA384_RSA_PKCS,CKM_SHA512_RSA_PKCS};
constexpr CK_MECHANISM_TYPE allMechanisms[]={CKM_RSA_PKCS,CKM_SHA256_RSA_PKCS,CKM_SHA384_RSA_PKCS,CKM_SHA512_RSA_PKCS,CKM_SHA256,CKM_SHA384,CKM_SHA512};
template<class T> Bytes bytes(const T& value) {
    auto p=reinterpret_cast<const uint8_t*>(&value); return {p,p+sizeof(value)};
}
Bytes boolean(bool value) { return {uint8_t(value?CK_TRUE:CK_FALSE)}; }
Bytes text(const std::string& value) { return {value.begin(),value.end()}; }
template<size_t N> void padded(CK_UTF8CHAR (&out)[N], const std::string& value) {
    std::memset(out,' ',N); std::memcpy(out,value.data(),std::min(N,value.size()));
}
struct Token {
    std::string reader,id,label;
    Bytes certificate,objectId,modulus,exponent,subject,issuer,serial;
    CK_DATE start{},end{};
    std::unique_ptr<cie_linux::Card> card;
    bool terminal=false,removed=false;
    Clock::time_point deadline{};
    std::map<CK_ATTRIBUTE_TYPE,Bytes> attributes(CK_OBJECT_HANDLE object) const;
};
struct Slot { CK_SLOT_ID id; std::string reader; Bytes atr; std::shared_ptr<Token> token; };
struct Session {
    std::shared_ptr<Token> token;
    CK_SLOT_ID slot;
    CK_FLAGS flags;
    bool finding=false,signing=false,multipart=false;
    bool verifying=false,verifyMultipart=false,hashMultipart=false;
    CK_MECHANISM_TYPE verifyMechanism=0;
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> hashing{nullptr,EVP_MD_CTX_free},verifier{nullptr,EVP_MD_CTX_free};
    std::vector<CK_OBJECT_HANDLE> found;
    size_t position=0;
    CK_MECHANISM_TYPE mechanism=0;
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> digest{nullptr,EVP_MD_CTX_free};
    void cancelSign() { signing=false; multipart=false; digest.reset(); }
    void cancelVerify() { verifying=false;verifyMultipart=false;verifier.reset(); }
};
struct State {
    std::mutex mutex;
    std::condition_variable wake;
    bool initialized=false,stop=true,finalizing=false;
    decltype(getpid()) process=0;
    std::thread timer;
    cie_linux::Readers readers;
    std::map<CK_SLOT_ID,Slot> slots;
    std::map<CK_SESSION_HANDLE,Session> sessions;
    std::deque<CK_SLOT_ID> events;
    CK_SLOT_ID nextSlot=1;
    CK_SESSION_HANDLE nextSession=1;
    ~State() {
        { std::lock_guard<std::mutex> lock(mutex); stop=true; wake.notify_all(); }
        if(timer.joinable()) timer.join();
    }
    void invalidate(Slot& slot) {
        if(slot.token) {slot.token->removed=true;slot.token->card.reset();slot.token.reset();}
    }
    void refresh() {
        auto current=readers.list();
        for(auto& [id,slot]:slots) {
            auto found=std::find_if(current.begin(),current.end(),[&](auto& r){return r.name==slot.reader;});
            Bytes atr=found==current.end()?Bytes{}:found->atr;
            if(atr!=slot.atr) {invalidate(slot);slot.atr=std::move(atr);events.push_back(id);wake.notify_all();}
        }
        for(auto& reader:current) {
            if(std::none_of(slots.begin(),slots.end(),[&](auto& entry){return entry.second.reader==reader.name;})) {
                auto id=nextSlot++;slots.emplace(id,Slot{id,reader.name,reader.atr,{}});
                events.push_back(id);wake.notify_all();
            }
        }
        // Coalesce events; unbounded queues must not accumulate in a browser.
        if(events.size()>128) events.erase(events.begin(),events.end()-128);
    }
    void expire() {
        for(auto& [id,slot]:slots) if(slot.token && slot.token->card && Clock::now()>=slot.token->deadline) {
            slot.token->card.reset();slot.token->terminal=false;
            for(auto& [handle,session]:sessions) if(session.token==slot.token) session.cancelSign();
        }
    }
} state;

void require(bool value,CK_RV error=CKR_ARGUMENTS_BAD) {if(!value)throw cie_linux::Error(error);}
template<class F> CK_RV boundary(F body) noexcept {
    try {
        // Reject a forked child's inherited state before taking inherited locks.
        if(state.process && state.process!=getpid()) return CKR_CRYPTOKI_NOT_INITIALIZED;
        std::lock_guard<std::mutex> lock(state.mutex);
        require(state.initialized,CKR_CRYPTOKI_NOT_INITIALIZED);state.expire();return body();
    } catch(const cie_linux::Error& e) {return e.code;}
      catch(const std::bad_alloc&) {return CKR_HOST_MEMORY;}
      catch(...) {return CKR_DEVICE_ERROR;}
}
Slot& slotById(CK_SLOT_ID id) {
    auto found=state.slots.find(id);require(found!=state.slots.end(),CKR_SLOT_ID_INVALID);return found->second;
}
Session& sessionById(CK_SESSION_HANDLE id) {
    auto found=state.sessions.find(id);require(found!=state.sessions.end(),CKR_SESSION_HANDLE_INVALID);
    require(!found->second.token->removed,CKR_DEVICE_REMOVED);return found->second;
}
Bytes encodedName(X509_NAME* name) {
    auto n=i2d_X509_NAME(name,nullptr);require(n>0,CKR_DEVICE_ERROR);Bytes out(n);auto p=out.data();i2d_X509_NAME(name,&p);return out;
}
CK_DATE date(const ASN1_TIME* value) {
    std::tm t{};require(ASN1_TIME_to_tm(value,&t)==1,CKR_DEVICE_ERROR);
    char encoded[9]{};require(std::strftime(encoded,sizeof(encoded),"%Y%m%d",&t)==8,CKR_DEVICE_ERROR);
    CK_DATE out{};std::memcpy(&out,encoded,8);return out;
}
Bytes number(EVP_PKEY* key,const char* name) {
    BIGNUM* raw=nullptr;require(EVP_PKEY_get_bn_param(key,name,&raw)==1,CKR_DEVICE_ERROR);
    std::unique_ptr<BIGNUM,decltype(&BN_free)> bn(raw,BN_free);Bytes out(BN_num_bytes(raw));BN_bn2bin(raw,out.data());return out;
}
std::shared_ptr<Token> tokenFor(Slot& slot) {
    require(!slot.atr.empty(),CKR_TOKEN_NOT_PRESENT);
    if(slot.token) return slot.token;
    auto card=std::make_unique<cie_linux::Card>(slot.reader);
    auto token=std::make_shared<Token>();token->reader=slot.reader;token->id=card->id;token->certificate=card->certificate;
    const auto* p=token->certificate.data();
    std::unique_ptr<X509,decltype(&X509_free)> cert(d2i_X509(nullptr,&p,long(token->certificate.size())),X509_free);
    require(cert && p==token->certificate.data()+token->certificate.size(),CKR_TOKEN_NOT_RECOGNIZED);
    std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)> key(X509_get_pubkey(cert.get()),EVP_PKEY_free);
    require(key && EVP_PKEY_base_id(key.get())==EVP_PKEY_RSA && EVP_PKEY_get_bits(key.get())==2048,CKR_TOKEN_NOT_RECOGNIZED);
    token->modulus=number(key.get(),OSSL_PKEY_PARAM_RSA_N);token->exponent=number(key.get(),OSSL_PKEY_PARAM_RSA_E);
    token->subject=encodedName(X509_get_subject_name(cert.get()));token->issuer=encodedName(X509_get_issuer_name(cert.get()));
    auto* serial=X509_get_serialNumber(cert.get());auto n=i2d_ASN1_INTEGER(serial,nullptr);
    require(n>0,CKR_TOKEN_NOT_RECOGNIZED);token->serial.resize(n);auto* out=token->serial.data();i2d_ASN1_INTEGER(serial,&out);
    token->objectId.resize(32);unsigned length=0;
    require(EVP_Digest(token->certificate.data(),token->certificate.size(),token->objectId.data(),&length,EVP_sha256(),nullptr)==1 && length==32,CKR_DEVICE_ERROR);
    constexpr char hex[]="0123456789abcdef";token->label="Firma con CIE ";
    for(size_t i=0;i<8;++i){token->label+=hex[token->objectId[i]>>4];token->label+=hex[token->objectId[i]&15];}
    token->start=date(X509_get0_notBefore(cert.get()));token->end=date(X509_get0_notAfter(cert.get()));
    // Public discovery never leaves an authenticated connection open while a
    // browser displays its PIN prompt. C_Login creates a fresh bound session.
    slot.token=token;return token;
}
std::map<CK_ATTRIBUTE_TYPE,Bytes> Token::attributes(CK_OBJECT_HANDLE object) const {
    require(object>=certificateObject && object<=privateObject,CKR_OBJECT_HANDLE_INVALID);
    CK_OBJECT_CLASS klass=object==certificateObject?CKO_CERTIFICATE:object==publicObject?CKO_PUBLIC_KEY:CKO_PRIVATE_KEY;
    std::map<CK_ATTRIBUTE_TYPE,Bytes> attrs{
        {CKA_CLASS,bytes(klass)},{CKA_TOKEN,boolean(true)},{CKA_PRIVATE,boolean(object==privateObject)},
        {CKA_LABEL,text(label)},{CKA_ID,objectId},{CKA_MODIFIABLE,boolean(false)},
        {CKA_SUBJECT,subject},{CKA_START_DATE,bytes(start)},{CKA_END_DATE,bytes(end)}
    };
    if(object==certificateObject) {
        attrs[CKA_CERTIFICATE_TYPE]=bytes(CK_CERTIFICATE_TYPE(CKC_X_509));attrs[CKA_VALUE]=certificate;
        attrs[CKA_ISSUER]=issuer;attrs[CKA_SERIAL_NUMBER]=serial;attrs[CKA_TRUSTED]=boolean(false);
    } else {
        attrs[CKA_KEY_TYPE]=bytes(CK_KEY_TYPE(CKK_RSA));attrs[CKA_MODULUS]=modulus;attrs[CKA_MODULUS_BITS]=bytes(CK_ULONG(2048));
        attrs[CKA_PUBLIC_EXPONENT]=exponent;attrs[CKA_LOCAL]=boolean(true);
        for(auto a:{CKA_ENCRYPT,CKA_DECRYPT,CKA_WRAP,CKA_UNWRAP,CKA_DERIVE,CKA_SIGN_RECOVER,CKA_VERIFY_RECOVER})attrs[a]=boolean(false);
        attrs[CKA_SIGN]=boolean(object==privateObject);attrs[CKA_VERIFY]=boolean(object==publicObject);
        attrs[CKA_ALLOWED_MECHANISMS]=Bytes(reinterpret_cast<const uint8_t*>(mechanisms),reinterpret_cast<const uint8_t*>(mechanisms)+sizeof(mechanisms));
        if(object==privateObject) {
            attrs[CKA_SENSITIVE]=boolean(true);attrs[CKA_ALWAYS_SENSITIVE]=boolean(true);
            attrs[CKA_EXTRACTABLE]=boolean(false);attrs[CKA_NEVER_EXTRACTABLE]=boolean(true);
            attrs[CKA_ALWAYS_AUTHENTICATE]=boolean(false);
        }
    }
    return attrs;
}
CK_RV initialize(CK_VOID_PTR input) noexcept {
    try {
        if(state.process && state.process!=getpid())return CKR_CRYPTOKI_NOT_INITIALIZED;
        std::lock_guard<std::mutex> lock(state.mutex);
        if(state.initialized || state.finalizing)return CKR_CRYPTOKI_ALREADY_INITIALIZED;
        if(input) {
            auto* args=static_cast<CK_C_INITIALIZE_ARGS_PTR>(input);
            if(args->pReserved || (args->flags&~CKF_OS_LOCKING_OK))return CKR_ARGUMENTS_BAD;
            bool any=args->CreateMutex||args->DestroyMutex||args->LockMutex||args->UnlockMutex;
            bool all=args->CreateMutex&&args->DestroyMutex&&args->LockMutex&&args->UnlockMutex;
            if(any&&!all)return CKR_ARGUMENTS_BAD;
            if(all&&!(args->flags&CKF_OS_LOCKING_OK))return CKR_CANT_LOCK;
        }
        state.process=getpid();state.stop=false;state.initialized=true;
        try {state.timer=std::thread([] {
            std::unique_lock<std::mutex> lock(state.mutex);
            while(!state.stop) {
                state.wake.wait_for(lock,std::chrono::milliseconds(250),[]{return state.stop;});
                if(!state.stop) {state.expire();try{state.refresh();}catch(...){}}
            }
        });} catch(...) {state.initialized=false;state.stop=true;throw;}
        return CKR_OK;
    } catch(...) {return CKR_HOST_MEMORY;}
}
CK_RV finalize(CK_VOID_PTR reserved) noexcept {
    if(reserved)return CKR_ARGUMENTS_BAD;
    if(state.process && state.process!=getpid())return CKR_CRYPTOKI_NOT_INITIALIZED;
    std::unique_lock<std::mutex> lock(state.mutex);
    if(!state.initialized)return CKR_CRYPTOKI_NOT_INITIALIZED;
    state.initialized=false;state.stop=true;state.finalizing=true;state.wake.notify_all();
    // Serialize finalize/reinitialize while the timer exits under this lock.
    auto timer=std::move(state.timer);lock.unlock();if(timer.joinable())timer.join();lock.lock();
    state.sessions.clear();state.slots.clear();state.events.clear();state.finalizing=false;return CKR_OK;
}
CK_RV info(CK_INFO_PTR out) {return boundary([&]() -> CK_RV {
    require(out);*out={};out->cryptokiVersion={2,20};out->libraryVersion={1,0};
    padded(out->manufacturerID,"Firma con CIE");padded(out->libraryDescription,"Firma con CIE PKCS11");return CKR_OK;
});}
CK_RV slots(CK_BBOOL present,CK_SLOT_ID_PTR out,CK_ULONG_PTR count) {return boundary([&]() -> CK_RV {
    require(count);state.refresh();std::vector<CK_SLOT_ID> ids;
    for(auto& [id,slot]:state.slots)if(!present || !slot.atr.empty())ids.push_back(id);
    auto capacity=*count;*count=ids.size();if(!out)return CKR_OK;
    require(capacity>=ids.size(),CKR_BUFFER_TOO_SMALL);std::copy(ids.begin(),ids.end(),out);return CKR_OK;
});}
CK_RV slotInfo(CK_SLOT_ID id,CK_SLOT_INFO_PTR out) {return boundary([&]() -> CK_RV {
    require(out);state.refresh();auto& slot=slotById(id);*out={};
    padded(out->slotDescription,slot.reader);padded(out->manufacturerID,"Firma con CIE");
    out->flags=CKF_REMOVABLE_DEVICE|CKF_HW_SLOT|(!slot.atr.empty()?CKF_TOKEN_PRESENT:0);return CKR_OK;
});}
CK_RV tokenInfo(CK_SLOT_ID id,CK_TOKEN_INFO_PTR out) {return boundary([&]() -> CK_RV {
    require(out);state.refresh();auto token=tokenFor(slotById(id));*out={};
    padded(out->label,token->label);padded(out->manufacturerID,"Firma con CIE");padded(out->model,"CIE RSA 2048");
    std::memset(out->serialNumber,' ',sizeof(out->serialNumber));std::memcpy(out->serialNumber,token->label.data()+7,16);
    out->flags=CKF_TOKEN_INITIALIZED|CKF_USER_PIN_INITIALIZED|CKF_LOGIN_REQUIRED|CKF_WRITE_PROTECTED;
    out->ulMaxSessionCount=64;out->ulMaxRwSessionCount=0;
    out->ulSessionCount=std::count_if(state.sessions.begin(),state.sessions.end(),[&](auto& item){return item.second.token==token;});
    out->ulMinPinLen=out->ulMaxPinLen=8;
    out->ulTotalPublicMemory=out->ulFreePublicMemory=out->ulTotalPrivateMemory=out->ulFreePrivateMemory=CK_UNAVAILABLE_INFORMATION;
    std::memset(out->utcTime,' ',sizeof(out->utcTime));return CKR_OK;
});}
CK_RV mechanismList(CK_SLOT_ID id,CK_MECHANISM_TYPE_PTR out,CK_ULONG_PTR count) {return boundary([&]() -> CK_RV {
    slotById(id);require(count);auto capacity=*count;*count=std::size(allMechanisms);if(!out)return CKR_OK;
    require(capacity>=std::size(allMechanisms),CKR_BUFFER_TOO_SMALL);std::copy(std::begin(allMechanisms),std::end(allMechanisms),out);return CKR_OK;
});}
CK_RV mechanismInfo(CK_SLOT_ID id,CK_MECHANISM_TYPE type,CK_MECHANISM_INFO_PTR out) {return boundary([&]() -> CK_RV {
    slotById(id);require(out);require(std::find(std::begin(allMechanisms),std::end(allMechanisms),type)!=std::end(allMechanisms),CKR_MECHANISM_INVALID);
    if(type==CKM_SHA256||type==CKM_SHA384||type==CKM_SHA512)*out={0,0,CKF_DIGEST};
    else *out={2048,2048,CKF_HW|CKF_SIGN|CKF_VERIFY};return CKR_OK;
});}
CK_RV openSession(CK_SLOT_ID id,CK_FLAGS flags,CK_VOID_PTR,CK_NOTIFY,CK_SESSION_HANDLE_PTR out) {return boundary([&]() -> CK_RV {
    require(out);*out=0;require(flags&CKF_SERIAL_SESSION,CKR_SESSION_PARALLEL_NOT_SUPPORTED);
    require(!(flags&~(CKF_SERIAL_SESSION|CKF_RW_SESSION)));require(!(flags&CKF_RW_SESSION),CKR_TOKEN_WRITE_PROTECTED);
    state.refresh();auto token=tokenFor(slotById(id));require(state.sessions.size()<64,CKR_SESSION_COUNT);
    auto handle=state.nextSession++;require(handle!=0,CKR_SESSION_COUNT);
    Session session;session.slot=id;session.flags=flags;session.token=std::move(token);
    state.sessions.emplace(handle,std::move(session));*out=handle;return CKR_OK;
});}
void releaseUnused(const std::shared_ptr<Token>& token) {
    if(std::none_of(state.sessions.begin(),state.sessions.end(),[&](auto& item){return item.second.token==token;})) {
        token->card.reset();token->terminal=false;
    }
}
CK_RV closeSession(CK_SESSION_HANDLE handle) {return boundary([&]() -> CK_RV {
    auto found=state.sessions.find(handle);require(found!=state.sessions.end(),CKR_SESSION_HANDLE_INVALID);
    auto token=found->second.token;state.sessions.erase(found);releaseUnused(token);return CKR_OK;
});}
CK_RV closeAll(CK_SLOT_ID id) {return boundary([&]() -> CK_RV {
    auto& slot=slotById(id);
    for(auto it=state.sessions.begin();it!=state.sessions.end();)if(it->second.slot==id)it=state.sessions.erase(it);else ++it;
    if(slot.token){slot.token->card.reset();slot.token->terminal=false;}return CKR_OK;
});}
CK_RV sessionInfo(CK_SESSION_HANDLE id,CK_SESSION_INFO_PTR out) {return boundary([&]() -> CK_RV {
    require(out);auto& session=sessionById(id);*out={session.slot,CK_STATE(session.token->card?CKS_RO_USER_FUNCTIONS:CKS_RO_PUBLIC_SESSION),session.flags,0};return CKR_OK;
});}
CK_RV login(CK_SESSION_HANDLE id,CK_USER_TYPE user,CK_UTF8CHAR_PTR pin,CK_ULONG length) {return boundary([&]() -> CK_RV {
    auto& session=sessionById(id);auto& token=*session.token;
    require(user==CKU_USER,CKR_USER_TYPE_INVALID);require(!token.card,CKR_USER_ALREADY_LOGGED_IN);
    require(!token.terminal,CKR_USER_NOT_LOGGED_IN);require(pin);require(length==8,CKR_PIN_LEN_RANGE);
    require(std::all_of(pin,pin+8,[](uint8_t c){return c>='0'&&c<='9';}),CKR_PIN_INVALID);
    std::array<char,8> secret{};std::copy(pin,pin+8,secret.begin());
    struct Wipe {std::array<char,8>& p;~Wipe(){cie_web::wipe(p.data(),p.size());}} wipe{secret};
    // Exactly one authenticate call, no PIN retention, suffix or fallback.
    token.terminal=true;
    auto card=std::make_unique<cie_linux::Card>(token.reader,token.id,token.certificate);
    auto status=card->authenticate(secret.data());if(status!=CKR_OK)return status;
    token.card=std::move(card);token.terminal=false;token.deadline=Clock::now()+idleLimit;return CKR_OK;
});}
CK_RV logout(CK_SESSION_HANDLE id) {return boundary([&]() -> CK_RV {
    auto token=sessionById(id).token;require(bool(token->card),CKR_USER_NOT_LOGGED_IN);
    token->card.reset();token->terminal=false;
    for(auto& [handle,session]:state.sessions)if(session.token==token)session.cancelSign();
    return CKR_OK;
});}
CK_RV attributes(CK_SESSION_HANDLE id,CK_OBJECT_HANDLE object,CK_ATTRIBUTE_PTR attrs,CK_ULONG count) {return boundary([&]() -> CK_RV {
    auto& session=sessionById(id);require(!count||attrs);require(count<=128);
    auto values=session.token->attributes(object);CK_RV result=CKR_OK;
    for(CK_ULONG i=0;i<count;++i) {
        auto& attr=attrs[i];auto found=values.find(attr.type);
        bool secret=object==privateObject && (attr.type==CKA_VALUE || (attr.type>=CKA_PRIVATE_EXPONENT&&attr.type<=CKA_COEFFICIENT));
        if(secret){attr.ulValueLen=CK_UNAVAILABLE_INFORMATION;result=CKR_ATTRIBUTE_SENSITIVE;continue;}
        if(found==values.end()) {attr.ulValueLen=CK_UNAVAILABLE_INFORMATION;if(result!=CKR_ATTRIBUTE_SENSITIVE)result=CKR_ATTRIBUTE_TYPE_INVALID;continue;}
        auto capacity=attr.ulValueLen;attr.ulValueLen=found->second.size();
        if(attr.pValue) {
            if(capacity<attr.ulValueLen){attr.ulValueLen=CK_UNAVAILABLE_INFORMATION;if(result==CKR_OK)result=CKR_BUFFER_TOO_SMALL;}
            else std::memcpy(attr.pValue,found->second.data(),found->second.size());
        }
    }
    return result;
});}
CK_RV objectSize(CK_SESSION_HANDLE id,CK_OBJECT_HANDLE object,CK_ULONG_PTR out) {return boundary([&]() -> CK_RV {
    require(out);sessionById(id).token->attributes(object);*out=CK_UNAVAILABLE_INFORMATION;return CKR_OK;
});}
CK_RV findInit(CK_SESSION_HANDLE id,CK_ATTRIBUTE_PTR attrs,CK_ULONG count) {return boundary([&]() -> CK_RV {
    auto& session=sessionById(id);require(!session.finding,CKR_OPERATION_ACTIVE);require(count<=64 && (!count||attrs));
    for(CK_ULONG i=0;i<count;++i)require(attrs[i].ulValueLen<=8192 && (!attrs[i].ulValueLen||attrs[i].pValue));
    session.found.clear();session.position=0;
    for(auto object:{certificateObject,publicObject,privateObject}) {
        auto values=session.token->attributes(object);bool match=true;
        for(CK_ULONG i=0;i<count;++i){auto found=values.find(attrs[i].type);
            if(found==values.end()||found->second.size()!=attrs[i].ulValueLen ||
                (attrs[i].ulValueLen && std::memcmp(found->second.data(),attrs[i].pValue,attrs[i].ulValueLen)))match=false;
        }
        if(match)session.found.push_back(object);
    }
    session.finding=true;return CKR_OK;
});}
CK_RV find(CK_SESSION_HANDLE id,CK_OBJECT_HANDLE_PTR out,CK_ULONG maximum,CK_ULONG_PTR count) {return boundary([&]() -> CK_RV {
    auto& s=sessionById(id);require(s.finding,CKR_OPERATION_NOT_INITIALIZED);require(count && (!maximum||out));
    *count=std::min<size_t>(maximum,s.found.size()-s.position);
    if(*count)std::copy_n(s.found.data()+s.position,*count,out);
    s.position+=*count;return CKR_OK;
});}
CK_RV findFinal(CK_SESSION_HANDLE id) {return boundary([&]() -> CK_RV {
    auto& s=sessionById(id);require(s.finding,CKR_OPERATION_NOT_INITIALIZED);s.finding=false;s.found.clear();return CKR_OK;
});}
const EVP_MD* digestFor(CK_MECHANISM_TYPE m) {
    return m==CKM_SHA256_RSA_PKCS||m==CKM_SHA256?EVP_sha256():m==CKM_SHA384_RSA_PKCS||m==CKM_SHA384?EVP_sha384():m==CKM_SHA512_RSA_PKCS||m==CKM_SHA512?EVP_sha512():nullptr;
}
CK_RV signInit(CK_SESSION_HANDLE id,CK_MECHANISM_PTR mechanism,CK_OBJECT_HANDLE key) {return boundary([&]() -> CK_RV {
    auto& s=sessionById(id);require(mechanism);require(key==privateObject,CKR_KEY_HANDLE_INVALID);
    require(!s.signing,CKR_OPERATION_ACTIVE);require(bool(s.token->card),CKR_USER_NOT_LOGGED_IN);
    require(!mechanism->pParameter && !mechanism->ulParameterLen,CKR_MECHANISM_PARAM_INVALID);
    require(std::find(std::begin(mechanisms),std::end(mechanisms),mechanism->mechanism)!=std::end(mechanisms),CKR_MECHANISM_INVALID);
    s.mechanism=mechanism->mechanism;
    if(auto* md=digestFor(s.mechanism)) {
        s.digest.reset(EVP_MD_CTX_new());require(s.digest && EVP_DigestInit_ex(s.digest.get(),md,nullptr)==1,CKR_HOST_MEMORY);
    }
    s.signing=true;return CKR_OK;
});}
Bytes digestInfo(const uint8_t* data,size_t size,CK_MECHANISM_TYPE mechanism) {
    auto* md=digestFor(mechanism);if(!md){Bytes out;if(size)out.assign(data,data+size);return out;}
    Bytes out={0x30,0,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,0,5,0,4,0};
    auto length=EVP_MD_get_size(md);out[1]=uint8_t(17+length);out[14]=length==32?1:length==48?2:3;out[18]=uint8_t(length);out.resize(19+length);
    unsigned n=0;require(EVP_Digest(data,size,out.data()+19,&n,md,nullptr)==1 && n==unsigned(length),CKR_DEVICE_ERROR);return out;
}
CK_RV signValue(Session& s,const Bytes& encoded,CK_BYTE_PTR output,CK_ULONG_PTR size) {
    require(size);require(bool(s.token->card),CKR_USER_NOT_LOGGED_IN);
    if(!cie_web::digestInfo(encoded.data(),uint32_t(encoded.size()))) {s.cancelSign();return CKR_DATA_INVALID;}
    auto capacity=*size;*size=256;
    if(!output)return CKR_OK;
    if(capacity<256)return CKR_BUFFER_TOO_SMALL;
    uint32_t length=256;CK_RV status=CKR_DEVICE_ERROR;
    try {status=s.token->card->sign(encoded,output,&length);}catch(const cie_linux::Error& e){status=e.code;}catch(...){status=CKR_DEVICE_ERROR;}
    s.cancelSign();
    if(status!=CKR_OK || length!=256) {
        s.token->card.reset();s.token->terminal=true;*size=0;return status==CKR_OK?CKR_DEVICE_ERROR:status;
    }
    *size=length;s.token->deadline=Clock::now()+idleLimit;return CKR_OK;
}
CK_RV sign(CK_SESSION_HANDLE id,CK_BYTE_PTR data,CK_ULONG length,CK_BYTE_PTR out,CK_ULONG_PTR size) {return boundary([&]() -> CK_RV {
    auto& s=sessionById(id);require(s.signing,CKR_OPERATION_NOT_INITIALIZED);
    if(!size || (length&&!data)){s.cancelSign();return CKR_ARGUMENTS_BAD;}
    if(s.multipart){s.cancelSign();return CKR_OPERATION_ACTIVE;}
    if(s.mechanism==CKM_RSA_PKCS && length>83){s.cancelSign();return CKR_DATA_LEN_RANGE;}
    auto encoded=digestInfo(data,length,s.mechanism);return signValue(s,encoded,out,size);
});}
CK_RV signUpdate(CK_SESSION_HANDLE id,CK_BYTE_PTR data,CK_ULONG length) {return boundary([&]() -> CK_RV {
    auto& s=sessionById(id);require(s.signing,CKR_OPERATION_NOT_INITIALIZED);require(!length||data);
    if(!s.digest){s.cancelSign();return CKR_FUNCTION_NOT_SUPPORTED;}
    if(EVP_DigestUpdate(s.digest.get(),data,length)!=1){s.cancelSign();return CKR_DEVICE_ERROR;}
    s.multipart=true;return CKR_OK;
});}
CK_RV signFinal(CK_SESSION_HANDLE id,CK_BYTE_PTR out,CK_ULONG_PTR size) {return boundary([&]() -> CK_RV {
    auto& s=sessionById(id);require(s.signing,CKR_OPERATION_NOT_INITIALIZED);require(size);
    if(!s.digest){s.cancelSign();return CKR_FUNCTION_NOT_SUPPORTED;}
    // Finalize a copy; length queries and small buffers keep the operation.
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> copy(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    require(copy && EVP_MD_CTX_copy_ex(copy.get(),s.digest.get())==1,CKR_HOST_MEMORY);
    std::array<uint8_t,64> digest{};unsigned n=0;require(EVP_DigestFinal_ex(copy.get(),digest.data(),&n)==1,CKR_DEVICE_ERROR);
    Bytes encoded={0x30,uint8_t(17+n),0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,uint8_t(n==32?1:n==48?2:3),5,0,4,uint8_t(n)};
    encoded.insert(encoded.end(),digest.begin(),digest.begin()+n);return signValue(s,encoded,out,size);
});}
CK_RV randomBytes(CK_SESSION_HANDLE id,CK_BYTE_PTR out,CK_ULONG size) {return boundary([&]() -> CK_RV {
    sessionById(id);require(out && size<=1048576);require(RAND_bytes(out,int(size))==1,CKR_DEVICE_ERROR);return CKR_OK;
});}
// Public software operations have independent state and never authenticate or
// invoke Card::sign. Length queries and short buffers do not consume a digest.
CK_RV digestInit(CK_SESSION_HANDLE id,CK_MECHANISM_PTR mechanism){return boundary([&]()->CK_RV{
 auto& s=sessionById(id);require(mechanism);require(!s.hashing,CKR_OPERATION_ACTIVE);
 require(!mechanism->pParameter&&!mechanism->ulParameterLen,CKR_MECHANISM_PARAM_INVALID);
 require(mechanism->mechanism==CKM_SHA256||mechanism->mechanism==CKM_SHA384||mechanism->mechanism==CKM_SHA512,CKR_MECHANISM_INVALID);
 s.hashing.reset(EVP_MD_CTX_new());if(!s.hashing||EVP_DigestInit_ex(s.hashing.get(),digestFor(mechanism->mechanism),nullptr)!=1){s.hashing.reset();return CKR_HOST_MEMORY;}
 s.hashMultipart=false;return CKR_OK;
});}
CK_RV digestOutput(Session& s,CK_BYTE_PTR data,CK_ULONG length,CK_BYTE_PTR out,CK_ULONG_PTR size,bool single){
 require(bool(s.hashing),CKR_OPERATION_NOT_INITIALIZED);
 if(!size||(length&&!data)||(single&&s.hashMultipart)){s.hashing.reset();return CKR_ARGUMENTS_BAD;}
 std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> copy(EVP_MD_CTX_new(),EVP_MD_CTX_free);
 require(copy&&EVP_MD_CTX_copy_ex(copy.get(),s.hashing.get())==1,CKR_HOST_MEMORY);
 if(single)require(EVP_DigestUpdate(copy.get(),data,length)==1,CKR_DEVICE_ERROR);
 std::array<uint8_t,64> value{};unsigned n=0;require(EVP_DigestFinal_ex(copy.get(),value.data(),&n)==1,CKR_DEVICE_ERROR);
 auto capacity=*size;*size=n;if(!out)return CKR_OK;if(capacity<n)return CKR_BUFFER_TOO_SMALL;
 std::memcpy(out,value.data(),n);s.hashing.reset();return CKR_OK;
}
CK_RV digest(CK_SESSION_HANDLE id,CK_BYTE_PTR data,CK_ULONG length,CK_BYTE_PTR out,CK_ULONG_PTR size){return boundary([&](){return digestOutput(sessionById(id),data,length,out,size,true);});}
CK_RV digestUpdate(CK_SESSION_HANDLE id,CK_BYTE_PTR data,CK_ULONG length){return boundary([&]()->CK_RV{
 auto& s=sessionById(id);require(bool(s.hashing),CKR_OPERATION_NOT_INITIALIZED);
 if((length&&!data)||EVP_DigestUpdate(s.hashing.get(),data,length)!=1){s.hashing.reset();return CKR_ARGUMENTS_BAD;}
 s.hashMultipart=true;return CKR_OK;
});}
CK_RV digestFinal(CK_SESSION_HANDLE id,CK_BYTE_PTR out,CK_ULONG_PTR size){return boundary([&](){return digestOutput(sessionById(id),nullptr,0,out,size,false);});}
CK_RV verifyInit(CK_SESSION_HANDLE id,CK_MECHANISM_PTR mechanism,CK_OBJECT_HANDLE key){return boundary([&]()->CK_RV{
 auto& s=sessionById(id);require(mechanism);require(key==publicObject,CKR_KEY_HANDLE_INVALID);require(!s.verifying,CKR_OPERATION_ACTIVE);
 require(!mechanism->pParameter&&!mechanism->ulParameterLen,CKR_MECHANISM_PARAM_INVALID);
 require(std::find(std::begin(mechanisms),std::end(mechanisms),mechanism->mechanism)!=std::end(mechanisms),CKR_MECHANISM_INVALID);
 if(auto* md=digestFor(mechanism->mechanism)){
  s.verifier.reset(EVP_MD_CTX_new());if(!s.verifier||EVP_DigestInit_ex(s.verifier.get(),md,nullptr)!=1){s.cancelVerify();return CKR_HOST_MEMORY;}
 }
 s.verifyMechanism=mechanism->mechanism;s.verifying=true;s.verifyMultipart=false;return CKR_OK;
});}
CK_RV verifyValue(Session& s,const Bytes& encoded,CK_BYTE_PTR signature,CK_ULONG size){
 s.cancelVerify();if(size!=256)return CKR_SIGNATURE_LEN_RANGE;require(signature);
 if(!cie_web::digestInfo(encoded.data(),uint32_t(encoded.size())))return CKR_DATA_INVALID;
 const auto* p=s.token->certificate.data();
 std::unique_ptr<X509,decltype(&X509_free)> cert(d2i_X509(nullptr,&p,long(s.token->certificate.size())),X509_free);
 require(bool(cert),CKR_DEVICE_ERROR);
 std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)> key(X509_get_pubkey(cert.get()),EVP_PKEY_free);
 std::unique_ptr<EVP_PKEY_CTX,decltype(&EVP_PKEY_CTX_free)> context(EVP_PKEY_CTX_new(key.get(),nullptr),EVP_PKEY_CTX_free);
 require(context&&EVP_PKEY_verify_init(context.get())>0&&EVP_PKEY_CTX_set_rsa_padding(context.get(),RSA_PKCS1_PADDING)>0,CKR_DEVICE_ERROR);
 auto result=EVP_PKEY_verify(context.get(),signature,size,encoded.data(),encoded.size());
 return result==1?CKR_OK:result==0?CKR_SIGNATURE_INVALID:CKR_DEVICE_ERROR;
}
CK_RV verify(CK_SESSION_HANDLE id,CK_BYTE_PTR data,CK_ULONG length,CK_BYTE_PTR signature,CK_ULONG size){return boundary([&]()->CK_RV{
 auto& s=sessionById(id);require(s.verifying,CKR_OPERATION_NOT_INITIALIZED);
 if((length&&!data)||s.verifyMultipart){s.cancelVerify();return CKR_ARGUMENTS_BAD;}
 if(s.verifyMechanism==CKM_RSA_PKCS&&length>83){s.cancelVerify();return CKR_DATA_LEN_RANGE;}
 auto encoded=digestInfo(data,length,s.verifyMechanism);return verifyValue(s,encoded,signature,size);
});}
CK_RV verifyUpdate(CK_SESSION_HANDLE id,CK_BYTE_PTR data,CK_ULONG length){return boundary([&]()->CK_RV{
 auto& s=sessionById(id);require(s.verifying,CKR_OPERATION_NOT_INITIALIZED);
 if(!s.verifier){s.cancelVerify();return CKR_FUNCTION_NOT_SUPPORTED;}
 if((length&&!data)||EVP_DigestUpdate(s.verifier.get(),data,length)!=1){s.cancelVerify();return CKR_ARGUMENTS_BAD;}
 s.verifyMultipart=true;return CKR_OK;
});}
CK_RV verifyFinal(CK_SESSION_HANDLE id,CK_BYTE_PTR signature,CK_ULONG size){return boundary([&]()->CK_RV{
 auto& s=sessionById(id);require(s.verifying,CKR_OPERATION_NOT_INITIALIZED);
 if(!s.verifier){s.cancelVerify();return CKR_FUNCTION_NOT_SUPPORTED;}
 std::array<uint8_t,64> value{};unsigned n=0;
 require(EVP_DigestFinal_ex(s.verifier.get(),value.data(),&n)==1,CKR_DEVICE_ERROR);
 Bytes encoded={0x30,uint8_t(17+n),0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,uint8_t(n==32?1:n==48?2:3),5,0,4,uint8_t(n)};
 encoded.insert(encoded.end(),value.begin(),value.begin()+n);return verifyValue(s,encoded,signature,size);
});}
CK_RV waitEvent(CK_FLAGS flags,CK_SLOT_ID_PTR out,CK_VOID_PTR reserved) noexcept {
    try {
        if(state.process && state.process!=getpid())return CKR_CRYPTOKI_NOT_INITIALIZED;
        std::unique_lock<std::mutex> lock(state.mutex);require(state.initialized,CKR_CRYPTOKI_NOT_INITIALIZED);
        require(out && !reserved && !(flags&~CKF_DONT_BLOCK));state.refresh();
        if(flags&CKF_DONT_BLOCK)require(!state.events.empty(),CKR_NO_EVENT);
        else state.wake.wait(lock,[]{return !state.events.empty()||!state.initialized;});
        require(state.initialized,CKR_CRYPTOKI_NOT_INITIALIZED);*out=state.events.front();state.events.pop_front();return CKR_OK;
    }catch(const cie_linux::Error& e){return e.code;}catch(...){return CKR_DEVICE_ERROR;}
}
template<class T>struct Unsupported;
template<class R,class... A>struct Unsupported<R(*)(A...)>{static R call(A...){return boundary([]{return CKR_FUNCTION_NOT_SUPPORTED;});}};
CK_FUNCTION_LIST functionList();
}
extern "C" CIE_PKCS11_EXPORT uint32_t CieLinuxWebAbiVersion() { return 1; }
extern "C" CIE_PKCS11_EXPORT CK_RV CIE_GET_FUNCTION_LIST(CK_FUNCTION_LIST_PTR_PTR out) {
    if(!out)return CKR_ARGUMENTS_BAD;
    static CK_FUNCTION_LIST functions=functionList();*out=&functions;return CKR_OK;
}
namespace {
CK_FUNCTION_LIST functionList() {
    CK_FUNCTION_LIST list{};list.version={2,20};
#define CK_PKCS11_FUNCTION_INFO(name) list.name=Unsupported<decltype(list.name)>::call;
#include "../../../backend/cie-pkcs11/PKCS11/pkcs11f.h"
#undef CK_PKCS11_FUNCTION_INFO
    list.C_GetFunctionList=CIE_GET_FUNCTION_LIST;list.C_Initialize=initialize;list.C_Finalize=finalize;list.C_GetInfo=info;
    list.C_GetSlotList=slots;list.C_GetSlotInfo=slotInfo;list.C_GetTokenInfo=tokenInfo;
    list.C_GetMechanismList=mechanismList;list.C_GetMechanismInfo=mechanismInfo;
    list.C_OpenSession=openSession;list.C_CloseSession=closeSession;list.C_CloseAllSessions=closeAll;list.C_GetSessionInfo=sessionInfo;
    list.C_Login=login;list.C_Logout=logout;list.C_GetAttributeValue=attributes;list.C_GetObjectSize=objectSize;
    list.C_FindObjectsInit=findInit;list.C_FindObjects=find;list.C_FindObjectsFinal=findFinal;
    list.C_SignInit=signInit;list.C_Sign=sign;list.C_SignUpdate=signUpdate;list.C_SignFinal=signFinal;
    list.C_DigestInit=digestInit;list.C_Digest=digest;list.C_DigestUpdate=digestUpdate;list.C_DigestFinal=digestFinal;
    list.C_VerifyInit=verifyInit;list.C_Verify=verify;list.C_VerifyUpdate=verifyUpdate;list.C_VerifyFinal=verifyFinal;
    list.C_GenerateRandom=randomBytes;list.C_WaitForSlotEvent=waitEvent;return list;
}
}
#ifdef CIE_PAIRING_TEST_SERVICE
// Only the separately linked software-test module exports this clock hook.
extern "C" CIE_PKCS11_EXPORT void CieTestExpire() {
    std::lock_guard<std::mutex> lock(state.mutex);
    for(auto& [id,slot]:state.slots)if(slot.token)slot.token->deadline=Clock::time_point{};
    state.expire();
}
#endif
