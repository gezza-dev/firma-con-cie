// SPDX-License-Identifier: BSD-3-Clause
#include "cie_bridge.h"
#include "middleware_abi.h"
#include "pin_operations.h"
#include "pdf_appearance.h"
#include "../backend/cie_sign_sdk/include/NetworkConfig.h"
#include "paired_store.h"
#include "web_cert_store.h"
#include "cie_enrollment_types.h"
#include "card_observation.h"
#include "enrollment_record.h"
#include "visible_output.h"
#include <map>
#include <set>
#include <algorithm>
#include <chrono>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <winscard.h>
#include "../platform/pcsc_utf8.h"
#else
#include <dlfcn.h>
#ifdef __APPLE__
#include <PCSC/winscard.h>
using LONG = int32_t;
using DWORD = uint32_t;
#else
#include <winscard.h>
#endif
#endif

namespace {
namespace fs = std::filesystem;
std::mutex gate;
void *middleware = nullptr, *adapter = nullptr;
std::string loadedPath, adapterPath;
VerifyFn verifyFn = nullptr;
InfoFn infoFn = nullptr;
CountFn countFn = nullptr;
ValidationFn validationFn = nullptr;
TemporalFn temporalFn = nullptr;
DocumentTemporalFn documentTemporalFn = nullptr;
IdentifyFn identifyFn = nullptr,identifyIdleFn=nullptr;
std::map<std::string,cie::CardObservation> observations;
using EnrollFn=int64_t (*)(const char*,const char*,char*,CieEnrollmentMaterial*);
EnrollFn enrollFn=nullptr;
SignFn signFn = nullptr;
PdfSignFn pdfSignFn=nullptr;
PdfInfoFn pdfInfoFn=nullptr;
PdfPrepareFn pdfPrepareFn=nullptr;
NetworkProbeFn networkProbeFn=nullptr;
P7mInfoFn p7mInfoFn=nullptr;
P7mPreservedFn p7mPreservedFn=nullptr;
ExtractFn extractFn=nullptr;
using CertificateNameFn=int (*)(const uint8_t*,uint32_t,char*,uint32_t);
CertificateNameFn certificateNameFn=nullptr,certificateCardNumberFn=nullptr;
using PairAuthFn=int64_t (*)(const char*,const char*,char*);
PairAuthFn pairAuthFn=nullptr;
using WebEnrollFn=int64_t (*)(const char*,const char*,char*,uint8_t*,uint32_t*);
WebEnrollFn webEnrollFn=nullptr;
PinFn changePinFn=nullptr,unblockPinFn=nullptr;

std::string quote(const std::string& value) {
    std::ostringstream out;
    out << '"';
    for (unsigned char c : value) {
        switch (c) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c);
            else out << c;
        }
    }
    out << '"';
    return out.str();
}
char* result(const std::string& json) {
    auto* out = static_cast<char*>(std::malloc(json.size() + 1));
    if (out) std::memcpy(out, json.c_str(), json.size() + 1);
    return out;
}
std::string error(const std::string& code, const std::string& message, int64_t native = 0) {
    return "{\"ok\":false,\"code\":" + quote(code) + ",\"message\":" + quote(message) +
        ",\"nativeCode\":" + std::to_string(native) + "}";
}
void wipe(char* pin) {
    if (!pin) return;
    size_t size = std::strlen(pin);
    volatile char* p = pin;
    while (size--) *p++ = 0;
}
struct PinGuard { char* pin; ~PinGuard() { wipe(pin); } };
struct NetworkGuard {const CieNetworkOptions* n;~NetworkGuard(){if(n&&n->size==sizeof(CieNetworkOptions)&&n->password){wipe(n->password);}}};
cie::NetworkConfig networkConfig(const CieNetworkOptions* n){
 if(!n)return {};if(n->size!=sizeof(CieNetworkOptions))throw std::invalid_argument("network_config_invalid");
 return cie::NetworkConfig::from(n->mode,n->host,n->port,n->username,n->password);
}
std::string checked(const char* value, const char* field) {
    if (!value || !*value) throw std::runtime_error(std::string("Campo mancante: ") + field);
    return value;
}
void* loadLibrary(const std::string& path) {
#ifdef _WIN32
    auto module = LoadLibraryExW(fs::u8path(path).c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    return reinterpret_cast<void*>(module);
#else
    return dlopen(path.c_str(), RTLD_LOCAL | RTLD_NOW);
#endif
}
void* symbol(void* handle, const char* name) {
#ifdef _WIN32
    return reinterpret_cast<void*>(GetProcAddress(reinterpret_cast<HMODULE>(handle), name));
#else
    return dlsym(handle, name);
#endif
}
void unload(void* handle) {
    if (!handle) return;
#ifdef _WIN32
    FreeLibrary(reinterpret_cast<HMODULE>(handle));
#else
    dlclose(handle);
#endif
}
std::string loaderError() {
#ifdef _WIN32
    return "Codice caricamento DLL: " + std::to_string(GetLastError());
#else
    const char* detail = dlerror();
    return detail ? detail : "Caricamento della libreria non riuscito";
#endif
}
bool readable(const fs::path& path) {
    return fs::is_regular_file(path) && std::ifstream(path, std::ios::binary).good();
}
std::string fixed(const char* text, size_t capacity) {
    size_t n = 0;
    while (n < capacity && text[n]) ++n;
    return std::string(text, n);
}
struct Context {
    SCARDCONTEXT value = 0;
    ~Context() { if (value) SCardReleaseContext(value); }
};
std::string detection(bool automatic=false) {
    Context context;
    LONG status = SCardEstablishContext(SCARD_SCOPE_USER, nullptr, nullptr, &context.value);
    if (status != SCARD_S_SUCCESS)
        return error("pcsc_unavailable", "Servizio smart card non disponibile", status);
    DWORD length = 0;
#ifdef _WIN32
#define CIE_LIST_READERS cie_pcsc::list
#define CIE_READER_STATE SCARD_READERSTATEA
#define CIE_STATUS_CHANGE cie_pcsc::change
#else
#define CIE_LIST_READERS SCardListReaders
#define CIE_READER_STATE SCARD_READERSTATE
#define CIE_STATUS_CHANGE SCardGetStatusChange
#endif
    status = CIE_LIST_READERS(context.value, nullptr, nullptr, &length);
    if (status == SCARD_E_NO_READERS_AVAILABLE) {
        if(automatic)observations.clear();
        return "{\"ok\":true,\"readers\":[],\"cieIdentificationAvailable\":" +
            std::string(identifyFn ? "true" : "false") + "}";
    }
    if (status != SCARD_S_SUCCESS || length > 1024 * 1024)
        return error("readers_failed", "Impossibile elencare i lettori", status);
    std::vector<char> names(length + 2, 0);
    status = CIE_LIST_READERS(context.value, nullptr, names.data(), &length);
    if (status != SCARD_S_SUCCESS) return error("readers_changed", "Ripetere il rilevamento", status);
    std::ostringstream json;
    json << "{\"ok\":true,\"cieIdentificationAvailable\":" << (identifyFn ? "true" : "false")
         << ",\"readers\":[";
    bool first = true;
    std::set<std::string> seen;
    for (size_t offset = 0; offset < length && names[offset];) {
        std::string reader = fixed(names.data() + offset, length - offset);
        offset += reader.size() + 1;
        if(seen.size()>=32)break;seen.insert(reader);
        CIE_READER_STATE state = {};
        state.szReader = reader.c_str();
        state.dwCurrentState = SCARD_STATE_UNAWARE;
        LONG readStatus = CIE_STATUS_CHANGE(context.value, 0, &state, 1);
        bool present = readStatus == SCARD_S_SUCCESS && (state.dwEventState & SCARD_STATE_PRESENT);
        char card[64] = {};
        bool occupied=readStatus==SCARD_S_SUCCESS&&(state.dwEventState&(SCARD_STATE_INUSE|SCARD_STATE_EXCLUSIVE));
        int identification=-1;
        if(automatic){
            auto& saved=observations[reader];
            std::ostringstream epoch;epoch<<present<<':'<<readStatus<<':'<<(state.dwEventState>>16)<<':';
            for(DWORD i=0;i<state.cbAtr&&i<sizeof(state.rgbAtr);++i)epoch<<std::hex<<int(state.rgbAtr[i])<<',';
            saved.update(epoch.str());auto now=std::chrono::steady_clock::now();
            if(identifyIdleFn&&saved.shouldIdentify(present,occupied,now)){
                identification=identifyIdleFn(reader.c_str(),card,sizeof(card));saved.identified(identification,card,now);
            }
            if(present&&!saved.id.empty()){std::memcpy(card,saved.id.c_str(),saved.id.size()+1);identification=0;}
            else if(saved.notCie)identification=-4;
            else if(present)identification=-3;
        }else identification=present&&identifyFn?identifyFn(reader.c_str(),card,sizeof(card)):-1;
        bool isCie = identification == 0;
        if (!first) json << ',';
        first = false;
        json << "{\"name\":" << quote(reader) << ",\"present\":" << (present ? "true" : "false")
             << ",\"eventCounter\":"<<(state.dwEventState>>16)
             << ",\"occupied\":"<<(occupied?"true":"false")
             << ",\"isCie\":" << (isCie ? "true" : "false") << ",\"cardId\":" << quote(card)
             << ",\"nativeCode\":" << readStatus << ",\"identificationCode\":" << identification << '}';
    }
    json << "]}";
    if(automatic){for(auto it=observations.begin();it!=observations.end();){if(!seen.count(it->first))it=observations.erase(it);else ++it;}}
    return json.str();
}
std::string verification(const char* input, bool* integrity = nullptr,const cie::NetworkConfig* network=nullptr) {
    if (integrity) *integrity = false;
    if (!verifyFn) return error("backend_missing", "Caricare prima il middleware");
    auto path = fs::u8path(checked(input, "documento"));
    if (!readable(path)) return error("input_missing", "Il documento non è un file leggibile");
    // The backend stores verification results globally. Hold gate until all
    // signer details have been copied, including when used from different isolates.
    auto endpoint=network?network->endpoint():"",credentials=network?network->credentials():"";
    struct Erase {std::string& s;~Erase(){volatile char* p=s.empty()?nullptr:&s[0];for(size_t i=0;i<s.size();++i)p[i]=0;}} erase{credentials};
    unsigned long returned = verifyFn(input, endpoint.empty()?nullptr:endpoint.c_str(),network?network->port:0,credentials.empty()?nullptr:credentials.c_str());
    unsigned long count = countFn();
    if (returned != count || count > 10000)
        return error("verification_failed", "Il middleware non ha potuto leggere il documento firmato", returned);
    std::ostringstream json;
    bool valid = count > 0;
    bool allTrusted = count > 0, allChecked = count > 0;
    json << "{\"ok\":true,\"signatureCount\":" << count << ",\"signers\":[";
    for (unsigned long i = 0; i < count; ++i) {
        CieVerifyInfo info = {};
        unsigned long status = infoFn(static_cast<int>(i), &info);
        if (status) return error("signer_failed", "Impossibile leggere il risultato della verifica", status);
        valid = valid && info.isSignValid;
        CIE_CERTIFICATE_VALIDATION trust{}; trust.size = sizeof(trust);
        bool checkedTrust = validationFn && validationFn(static_cast<int>(i), &trust) == 0 &&
            trust.size == sizeof(trust) && trust.status != CIE_TRUST_NOT_CHECKED;
        bool trusted = checkedTrust && trust.status == CIE_TRUST_TRUSTED;
        allTrusted = allTrusted && trusted; allChecked = allChecked && checkedTrust;
        const char* trustStatus = !checkedTrust ? "not_checked" : trusted ? "trusted" :
            trust.status == CIE_TRUST_UNTRUSTED ? "untrusted" : trust.status == CIE_TRUST_INVALID ? "invalid" : "unknown";
        CIE_TEMPORAL_VALIDATION temporal{}; temporal.size=sizeof(temporal);
        bool checkedTime = temporalFn && temporalFn(static_cast<int>(i), &temporal)==0 &&
            temporal.size==sizeof(temporal) && temporal.timestampStatus!=CIE_TS_NOT_CHECKED;
        const char* timestampStatus = !checkedTime ? "not_checked" : temporal.timestampStatus==CIE_TS_ABSENT ? "absent" :
            temporal.timestampStatus==CIE_TS_VERIFIED ? "verified" : temporal.timestampStatus==CIE_TS_INVALID ? "invalid" : "indeterminate";
        if (i) json << ',';
        json << "{\"name\":" << quote(fixed(info.name, sizeof(info.name)))
             << ",\"surname\":" << quote(fixed(info.surname, sizeof(info.surname)))
             << ",\"commonName\":" << quote(fixed(info.cn, sizeof(info.cn)))
             << ",\"issuer\":" << quote(fixed(info.cadn, sizeof(info.cadn)))
             << ",\"signingTime\":" << quote(fixed(info.signingTime, sizeof(info.signingTime)))
             << ",\"signatureValid\":" << (info.isSignValid ? "true" : "false")
             << ",\"certificateWithinValidity\":" << (info.isCertValid ? "true" : "false")
             << ",\"revocationStatus\":" << info.CertRevocStatus
             << ",\"trustChainChecked\":" << (checkedTrust ? "true" : "false")
             << ",\"trustChainValidated\":" << (trusted ? "true" : "false")
             << ",\"trustChainStatus\":" << quote(trustStatus)
             << ",\"trustChainError\":" << trust.error
             << ",\"trustChainReason\":" << quote(fixed(trust.reason, sizeof(trust.reason)))
             << ",\"trustSource\":" << quote(fixed(trust.trustSource, sizeof(trust.trustSource)))
             << ",\"chainLength\":" << trust.chainLength
             << ",\"chainRevocationStatus\":" << (checkedTrust ? trust.revocationStatus : 3)
             << ",\"revocationSource\":" << quote(trust.revocationType == 1 ? "ocsp" : trust.revocationType == 2 ? "crl" : "unavailable")
             << ",\"timestampStatus\":" << quote(timestampStatus)
             << ",\"timestampReason\":" << quote(fixed(temporal.timestampReason,sizeof(temporal.timestampReason)))
             << ",\"timestampTime\":" << quote(fixed(temporal.utcTime,sizeof(temporal.utcTime)))
             << ",\"timestampPolicy\":" << quote(fixed(temporal.policy,sizeof(temporal.policy)))
             << ",\"timestampCount\":" << temporal.timestampCount
             << ",\"historicalStatus\":" << quote(!checkedTime || temporal.historicalStatus==CIE_HISTORY_INDETERMINATE ? "indeterminate" :
                    temporal.historicalStatus==CIE_HISTORY_VALID ? "valid_at_timestamp" : "invalid_at_timestamp")
             << ",\"historicalReason\":" << quote(fixed(temporal.historicalReason,sizeof(temporal.historicalReason)))
             << ",\"tsaHistoricalRevocationStatus\":" << (checkedTime ? temporal.tsaRevocationStatus : 3)
             << ",\"signerHistoricalRevocationStatus\":" << (checkedTime ? temporal.signerRevocationStatus : 3)
             << ",\"revocationReason\":" << quote(fixed(trust.revocationReason, sizeof(trust.revocationReason))) << '}';
    }
    CIE_TEMPORAL_VALIDATION docTime{}; docTime.size=sizeof(docTime);
    bool checkedDocTime=documentTemporalFn && documentTemporalFn(&docTime)==0 && docTime.size==sizeof(docTime) && docTime.timestampStatus!=CIE_TS_NOT_CHECKED;
    json << "],\"documentTimestampCount\":" << (checkedDocTime ? docTime.timestampCount : 0)
         << ",\"documentTimestampStatus\":" << quote(!checkedDocTime ? "not_checked" : docTime.timestampStatus==CIE_TS_ABSENT ? "absent" :
            docTime.timestampStatus==CIE_TS_VERIFIED ? "verified" : docTime.timestampStatus==CIE_TS_INVALID ? "invalid" : "indeterminate")
         << ",\"documentTimestampReason\":" << quote(fixed(docTime.timestampReason,sizeof(docTime.timestampReason)))
         << ",\"documentTimestampTime\":" << quote(fixed(docTime.utcTime,sizeof(docTime.utcTime)))
         << ",\"trustChainChecked\":" << (allChecked ? "true" : "false")
         << ",\"trustChainValidated\":" << (allTrusted ? "true" : "false") << '}';
    if (integrity) *integrity = valid;
    return json.str();
}
template<class F> char* guarded(F operation) noexcept {
    std::lock_guard<std::mutex> lock(gate);
    try { return result(operation()); }
    catch (const std::invalid_argument&) { return result(error("network_config_invalid", "Configurazione proxy non valida")); }
    catch (const std::exception& e) { return result(error("bridge_error", e.what())); }
    catch (...) { return result(error("bridge_error", "Errore nel componente nativo")); }
}
}

uint32_t cie_bridge_abi_version(void) { return 1; }
void cie_bridge_free(char* value) { std::free(value); }
char* cie_bridge_load(const char* input, const char* cardInput) {
    return guarded([&]() -> std::string {
        auto path = fs::absolute(fs::u8path(checked(input, "middleware")));
        if (!readable(path)) return error("backend_missing", "Middleware non trovato nel percorso selezionato");
        if (middleware && path.u8string() != loadedPath)
            return error("restart_required", "Riavviare l’applicazione prima di cambiare middleware");
        if (!middleware) {
            void* handle = loadLibrary(path.u8string());
            if (!handle) return error("backend_load_failed", loaderError());
            auto verify = reinterpret_cast<VerifyFn>(symbol(handle, "verificaConCIE"));
            auto info = reinterpret_cast<InfoFn>(symbol(handle, "getVerifyInfo"));
            auto count = reinterpret_cast<CountFn>(symbol(handle, "getNumberOfSign"));
            if (!verify || !info || !count) {
                unload(handle);
                return error("incompatible_backend", "Mancano le API di verifica previste dal backend v1.5.2");
            }
            middleware = handle; verifyFn = verify; infoFn = info; countFn = count;
            validationFn = reinterpret_cast<ValidationFn>(symbol(handle, "getCertificateValidation"));
            temporalFn = reinterpret_cast<TemporalFn>(symbol(handle, "getTemporalValidation"));
            networkProbeFn=reinterpret_cast<NetworkProbeFn>(symbol(handle,"cie_document_network_probe"));
            documentTemporalFn = reinterpret_cast<DocumentTemporalFn>(symbol(handle, "getDocumentTimestampValidation"));
            p7mInfoFn=reinterpret_cast<P7mInfoFn>(symbol(handle,"cie_document_p7m_info"));
            p7mPreservedFn=reinterpret_cast<P7mPreservedFn>(symbol(handle,"cie_document_p7m_preserved"));
            certificateNameFn=reinterpret_cast<CertificateNameFn>(symbol(handle,"cie_document_certificate_name"));
            certificateCardNumberFn=reinterpret_cast<CertificateNameFn>(symbol(handle,"cie_document_certificate_card_number"));
            pdfInfoFn=reinterpret_cast<PdfInfoFn>(symbol(handle,"cie_document_pdf_info"));
            pdfPrepareFn=reinterpret_cast<PdfPrepareFn>(symbol(handle,"cie_document_prepare_appearance"));
            extractFn=reinterpret_cast<ExtractFn>(symbol(handle,"estraiP7m"));
            loadedPath = path.u8string();
        }
        // Keep modules loaded until process exit; unload during an active card
        // operation or while callbacks exist would invalidate native addresses.
        if (!adapter && cardInput && *cardInput) {
            auto companion = fs::absolute(fs::u8path(cardInput));
            void* handle = loadLibrary(companion.u8string());
            if (!handle) return error("card_adapter_load_failed", loaderError());
            auto identify = reinterpret_cast<IdentifyFn>(symbol(handle, "cie_card_identify"));
            auto sign = reinterpret_cast<SignFn>(symbol(handle, "cie_card_sign"));
            if (!identify || !sign) {
                unload(handle);
                return error("incompatible_card_adapter", "Adattatore carta incompatibile");
            }
            adapter = handle; identifyIdleFn=reinterpret_cast<IdentifyFn>(symbol(handle,"cie_card_identify_idle"));enrollFn=reinterpret_cast<EnrollFn>(symbol(handle,"cie_card_enroll_v2")); identifyFn = identify; signFn = sign; adapterPath = companion.u8string();
            pairAuthFn=reinterpret_cast<PairAuthFn>(symbol(handle,"cie_card_pair_authenticate"));
            webEnrollFn=reinterpret_cast<WebEnrollFn>(symbol(handle,"cie_card_web_enroll"));
            pdfSignFn=reinterpret_cast<PdfSignFn>(symbol(handle,"cie_card_sign_pdf"));
            changePinFn=reinterpret_cast<PinFn>(symbol(handle,"cie_card_change_pin"));
            unblockPinFn=reinterpret_cast<PinFn>(symbol(handle,"cie_card_unblock_pin"));
        }
        return "{\"ok\":true,\"canObserveCards\":"+std::string(identifyIdleFn?"true":"false")+",\"enrollmentVersion\":"+(enrollFn&&cie_pairing::supported()?"2":"0")+",\"abiVersion\":1,\"middleware\":" + quote(loadedPath) +
            ",\"cardAdapter\":" + quote(adapterPath) + ",\"canSign\":" +
            (signFn ? "true" : "false") + ",\"canPair\":"+(pairAuthFn && cie_pairing::supported()?"true":"false") + ",\"canChangePin\":"+(changePinFn ? "true":"false")+
            ",\"canUnblockPin\":"+(unblockPinFn ? "true":"false")+",\"canConfigureWeb\":"+(webEnrollFn ? "true":"false")+
            ",\"canSignPdfAppearance\":"+(pdfSignFn && pdfInfoFn && pdfPrepareFn ? "true":"false")+
            ",\"canCosign\":"+(p7mInfoFn && p7mPreservedFn ? "true":"false")+
            ",\"canPreviewPdf\":"+(pdfInfoFn ? "true":"false")+
            ",\"canExtract\":"+(extractFn ? "true":"false")+",\"canConfigureNetwork\":"+(networkProbeFn ? "true":"false")+"}";
    });
}
char* cie_bridge_observe(void){
 // Do not queue background observation behind a long verification/private call.
 std::unique_lock<std::mutex> lock(gate,std::try_to_lock);if(!lock.owns_lock())return result(error("busy","Carta in uso: attendi"));
 try{return result(detection(true));}catch(...){return result(error("pcsc_unavailable","Rilevamento temporaneamente non disponibile"));}
}
char* cie_bridge_detect(void) { return guarded([] { return detection(); }); }
char* cie_bridge_verify(const char* input) { return guarded([&] { return verification(input); }); }
char* cie_bridge_verify_network(const char* input,const CieNetworkOptions* options){
 NetworkGuard secret{options};return guarded([&]{auto n=networkConfig(options);return verification(input,nullptr,&n);});
}
char* cie_bridge_network_probe(const CieNetworkOptions* options){
 NetworkGuard secret{options};return guarded([&]{auto n=networkConfig(options);
  if(!networkProbeFn)return error("network_unavailable","Test connessione non disponibile nel runtime");
  CieNetworkProbe probe{};probe.size=sizeof(probe);
  if(networkProbeFn(options,&probe))return error("network_config_invalid","Configurazione proxy non valida");
  return std::string("{\"ok\":")+(probe.transport_code==0?"true":"false")+",\"code\":\""+(probe.transport_code==0?"network_ok":"network_failed")+"\",\"transportCode\":"+std::to_string(probe.transport_code)+",\"httpStatus\":"+std::to_string(probe.http_status)+"}";
 });
}
static char* signDocument(const char* reader,const char* expected,const char* input,
    const char* output,const char* format,char* pin,const CiePdfAppearance* appearance,const CieNetworkOptions* options=nullptr,bool paired=false,bool replace=false) {
    PinGuard secret{pin};NetworkGuard proxySecret{options};
    return guarded([&]() -> std::string {
        auto network=networkConfig(options);
        if (!signFn) return error("signing_unavailable", "Adattatore di firma con PIN completo non disponibile su questa piattaforma");
        auto readerName = checked(reader, "lettore");
        auto card = checked(expected, "identificativo carta");
        auto source = fs::absolute(fs::u8path(checked(input, "documento")));
        auto destination = fs::absolute(fs::u8path(checked(output, "destinazione")));
        auto type = checked(format, "formato");
        if (!pin || std::strlen(pin) != (paired?4:8) || !std::all_of(pin, pin + (paired?4:8), [](char c) { return c >= '0' && c <= '9'; }))
            return error("invalid_pin", "Inserire le otto cifre del PIN completo");
        if (type != "pdf" && type != "p7m" && type != "cosign") return error("invalid_format", "Formato non supportato");
        if (!readable(source)) return error("input_missing", "Il documento da firmare non è leggibile");
        uint32_t previousSignatures=0;
        if(type=="cosign" && (!p7mInfoFn || !p7mPreservedFn || p7mInfoFn(source.u8string().c_str(),&previousSignatures)))
            return error("cosign_input_invalid","Cofirma non disponibile: scegliere un P7M con contenuto e firme crittograficamente valide. Nessun PIN inviato alla carta.");
        if(appearance) {
            if(type!="pdf" || !pdfSignFn || !pdfPrepareFn) return error("appearance_unavailable","Firma PDF grafica non disponibile nel runtime");
            CiePdfAppearance raw{};
            if(!cie_pdf::valid(*appearance) || pdfPrepareFn(source.u8string().c_str(),appearance,&raw))
                return error("invalid_appearance","Anteprima, pagina o immagine della firma non valide. Nessun PIN inviato alla carta.");
        }
        const auto targetStatus=fs::symlink_status(destination);
        const bool targetExists=fs::exists(targetStatus);
        if(targetExists && (!replace || !fs::is_regular_file(targetStatus)))
            return error("output_exists", "Scegliere un file normale o confermare la sostituzione del file esistente");
        if(source==destination)return error("output_exists","Usare una copia privata del documento prima della sostituzione");
        if (!fs::is_directory(destination.parent_path())) return error("output_missing", "Cartella di destinazione inesistente");
        cie::OutputStaging staging(destination.parent_path(),type=="cosign"?"p7m":type);
        if(replace && targetExists)staging.prepareReplacement(destination);
        const auto& temporary=staging.file;
        cie_pairing::Secret complete;
        char* signingPin=pin;
        if(paired){
            try{if(!cie_pairing::read(card,complete))return error("pairing_required","CIE non abbinata. Abbinare la carta o usare il PIN completo.");}
            catch(...){return error("pairing_store_unavailable","Abbinamento non leggibile. Rimuovi la CIE dalla Home e ripeti l’abbinamento con il PIN completo. Nessun PIN è stato inviato alla carta.");}
            std::memcpy(complete.bytes.data()+4,pin,4);complete.bytes[8]=0;signingPin=complete.bytes.data();
        }
        // The adapter re-identifies the selected card BEFORE checking the PIN.
        // This is exactly one SDK invocation; no implicit PIN retries/enrollment.
        int64_t status = appearance ? pdfSignFn(readerName.c_str(),card.c_str(),source.u8string().c_str(),temporary.u8string().c_str(),signingPin,appearance) :
            signFn(readerName.c_str(), card.c_str(), source.u8string().c_str(),temporary.u8string().c_str(), type.c_str(), signingPin);
        wipe(signingPin);
        wipe(pin);
        if (status) {
            if(status==-22)return error("cosign_input_invalid","P7M non valido per la cofirma. Nessun PIN inviato alla carta.",status);
            if(status==-20 || status==-21)return error("pdf_invalid","PDF o segno grafico non validi. Nessun PIN inviato alla carta.",status);
            if (status == 0x6983 || status == 0xA4) return error("pin_locked", "PIN bloccato: usare Sblocca Carta con il PUK", status);
            if ((status & 0xFFF0) == 0x63C0) return error("pin_incorrect", "PIN errato. Nessun nuovo tentativo automatico", status);
            if (status == -10) return error("card_changed", "La carta sul lettore è cambiata: ripetere il rilevamento", status);
            return error("signing_failed", "Firma non completata dal middleware", status);
        }
        if (!readable(temporary) || fs::file_size(temporary) == 0)
            return error("output_invalid", "L’SDK non ha prodotto un documento firmato");
        bool valid = false;
        auto report = verification(temporary.u8string().c_str(), &valid,&network);
        if (!valid) return error("post_sign_verification_failed",
            "Il controllo crittografico del documento prodotto non è riuscito. Nessun file pubblicato");
        if(type=="cosign" && p7mPreservedFn(source.u8string().c_str(),temporary.u8string().c_str()))
            return error("cosign_preservation_failed","Il risultato non conserva tutte le firme originali. Nessun file pubblicato");
        // An explicitly confirmed replacement is published only after all
        // cryptographic checks. Failures leave the previous document untouched.
        const auto ec=staging.publish(destination,replace && targetExists);
        if (ec) return error("output_publish_failed", "Impossibile salvare il documento (la destinazione potrebbe essere cambiata): " + ec.message(), ec.value());
        return "{\"ok\":true,\"output\":" + quote(destination.u8string()) +
            ",\"verification\":" + report + "}";
    });
}

char* cie_bridge_sign(const char* r,const char* c,const char* i,const char* o,const char* f,char* p) {
    return signDocument(r,c,i,o,f,p,nullptr);
}
char* cie_bridge_sign_pdf(const char* r,const char* c,const char* i,const char* o,char* p,
    const char* image,int32_t page,double left,double top,double width,double height) {
    CiePdfAppearance a{sizeof(CiePdfAppearance),page,left,top,width,height,image};
    return signDocument(r,c,i,o,"pdf",p,&a);
}

char* cie_bridge_sign_network_replace(const char* r,const char* c,const char* i,const char* o,const char* f,char* p,const CieNetworkOptions* n){return signDocument(r,c,i,o,f,p,nullptr,n,false,true);}
char* cie_bridge_sign_pdf_network_replace(const char* r,const char* c,const char* i,const char* o,char* p,const char* image,int32_t page,double left,double top,double width,double height,const CieNetworkOptions* n){CiePdfAppearance a{sizeof(CiePdfAppearance),page,left,top,width,height,image};return signDocument(r,c,i,o,"pdf",p,&a,n,false,true);}
char* cie_bridge_sign_paired_network_replace(const char* r,const char* c,const char* i,const char* o,const char* f,char* p,const CieNetworkOptions* n){return signDocument(r,c,i,o,f,p,nullptr,n,true,true);}
char* cie_bridge_sign_pdf_paired_network_replace(const char* r,const char* c,const char* i,const char* o,char* p,const char* image,int32_t page,double left,double top,double width,double height,const CieNetworkOptions* n){CiePdfAppearance a{sizeof(CiePdfAppearance),page,left,top,width,height,image};return signDocument(r,c,i,o,"pdf",p,&a,n,true,true);}

char* cie_bridge_sign_network(const char* r,const char* c,const char* i,const char* o,const char* f,char* p,const CieNetworkOptions* n){return signDocument(r,c,i,o,f,p,nullptr,n);}
char* cie_bridge_sign_pdf_network(const char* r,const char* c,const char* i,const char* o,char* p,const char* image,int32_t page,double left,double top,double width,double height,const CieNetworkOptions* n){
 CiePdfAppearance a{sizeof(CiePdfAppearance),page,left,top,width,height,image};return signDocument(r,c,i,o,"pdf",p,&a,n);
}
char* cie_bridge_signing_info(const char* input) {
    return guarded([&]() -> std::string {
        auto path=fs::u8path(checked(input,"documento"));
        if(!readable(path) || fs::file_size(path)>256*1024*1024)
            return error("input_missing","Documento non leggibile o troppo grande (massimo 256 MiB)");
        CiePdfPageInfo info{};info.size=sizeof(info);
        bool pdf=pdfInfoFn && pdfInfoFn(path.u8string().c_str(),0,&info)==0 && info.pageCount>0;
        uint32_t count=0;
        bool cms=p7mInfoFn && p7mInfoFn(path.u8string().c_str(),&count)==0 && count>0;
        return std::string("{\"ok\":true,\"pdfSupported\":")+(pdf?"true":"false")+
            ",\"cosignSupported\":"+(cms && p7mPreservedFn?"true":"false")+
            ",\"signatureCount\":"+std::to_string(count)+"}";
    });
}
char* cie_bridge_pdf_info(const char* input,int32_t page) {
    return guarded([&]() -> std::string {
        if(!pdfInfoFn)return error("preview_unavailable","Anteprima PDF non disponibile nel runtime");
        auto path=fs::u8path(checked(input,"documento"));
        if(!readable(path))return error("input_missing","PDF non leggibile");
        CiePdfPageInfo info{};info.size=sizeof(info);
        auto status=pdfInfoFn(path.u8string().c_str(),page,&info);
        if(status)return error("pdf_invalid","PDF o pagina non supportati. Verificare che il documento non sia protetto da password.",status);
        std::ostringstream out;out<<"{\"ok\":true,\"pageCount\":"<<info.pageCount<<",\"rotation\":"<<info.rotation
            <<",\"width\":"<<info.width<<",\"height\":"<<info.height<<"}";return out.str();
    });
}
char* cie_bridge_extract(const char* input,const char* output) {
    return guarded([&]() -> std::string {
        if(!extractFn)return error("extraction_unavailable","Estrazione P7M non disponibile nel runtime");
        auto source=fs::absolute(fs::u8path(checked(input,"documento")));
        auto destination=fs::absolute(fs::u8path(checked(output,"destinazione")));
        if(!readable(source) || fs::file_size(source)>256*1024*1024)return error("input_missing","File P7M non leggibile o troppo grande (massimo 256 MiB)");
        auto extension=source.extension().u8string();std::transform(extension.begin(),extension.end(),extension.begin(),[](unsigned char c){return char(std::tolower(c));});
        if(extension!=".p7m")return error("invalid_format","Selezionare un contenitore CAdES P7M");
        if(source==destination || fs::exists(destination))return error("output_exists","Scegliere un nuovo nome: i file esistenti non vengono sovrascritti");
        if(!fs::is_directory(destination.parent_path()))return error("output_missing","Cartella di destinazione inesistente");
        cie::OutputStaging staging(destination.parent_path(),"document");
        const auto& temporary=staging.file;
        auto status=extractFn(source.u8string().c_str(),temporary.u8string().c_str());
        if(status || !readable(temporary))return error("extraction_failed","Il file non contiene un documento estraibile o è danneggiato",status);
        auto bytes=fs::file_size(temporary);const auto ec=staging.publish(destination);
        if(ec)return error("output_publish_failed","Impossibile salvare il documento (la destinazione potrebbe essere cambiata): "+ec.message(),ec.value());
        return "{\"ok\":true,\"output\":"+quote(destination.u8string())+",\"bytes\":"+std::to_string(bytes)+
            ",\"integrityChecked\":false,\"message\":\"Documento estratto. L’estrazione non equivale alla verifica della firma.\"}";
    });
}

static char* pinOperation(const char* reader,const char* expected,char* authentication,char* replacement,bool unblock) {
    cie_pin::Secrets secrets{authentication,replacement};
    return guarded([&]() -> std::string {
        auto function=unblock ? unblockPinFn : changePinFn;
        if(!function) return error("pin_operation_unavailable","Operazione carta non disponibile in questo runtime");
        auto name=checked(reader,"lettore"),card=checked(expected,"identificativo carta");
        if(!cie_pin::digits(authentication)) return error(unblock ? "invalid_puk":"invalid_pin",unblock ? "Inserire le otto cifre del PUK":"Inserire le otto cifre del PIN attuale");
        if(!cie_pin::newPin(replacement)) return error("invalid_new_pin","Il nuovo PIN deve contenere otto cifre");
        bool cleanupFailed=false;int64_t cleanupNative=0;
        if(cie_pairing::supported()){
            try{cie_pairing::invalidate(card);}
            catch(...){auto out=error("pairing_invalidation_unavailable","Impossibile disabilitare in modo persistente l’abbinamento locale. Operazione non avviata: nessun PIN o PUK inviato alla carta.");out.pop_back();return out+",\"outcome\":\"not_started\"}";}
            // Both deletions are attempted independently. Never block card mutation
            // on Keychain/Credential Manager failure after durable invalidation.
            auto cleanup=[&](auto fn){try{fn(card);}catch(const cie_pairing::StoreError& e){cleanupFailed=true;if(!cleanupNative)cleanupNative=e.nativeCode;}catch(...){cleanupFailed=true;}};
            cleanup(cie_pairing::eraseRecord);
        }
        auto perform=[&]()->std::string {
        int phase=0;
        int64_t status=function(name.c_str(),card.c_str(),authentication,replacement,&phase);
        if(phase==2 || (status==0 && phase!=3))
            return "{\"ok\":false,\"code\":\"pin_operation_indeterminate\",\"outcome\":\"indeterminate\",\"message\":\"La risposta alla modifica del PIN non è stata ricevuta. Il PIN potrebbe essere già cambiato: non ripetere automaticamente l’operazione.\"}";
        if(status==-10) return error("card_changed","La carta è cambiata: ripetere il rilevamento prima di continuare",status);
        if(phase==1 && ((status&0xFFF0)==0x63C0 || status==0x6983)) {
            int attempts=status==0x6983 ? 0 : int(status&15);
            bool locked=attempts==0;
            auto code=unblock ? (locked ? "puk_locked":"puk_incorrect") : (locked ? "pin_locked":"pin_incorrect");
            auto message=unblock ? (locked ? "PUK bloccato. Non effettuare altri tentativi: rivolgersi all’assistenza CIE." : "PUK errato. Nessun nuovo tentativo automatico.") :
                (locked ? "PIN bloccato: usare Sblocca Carta con il PUK." : "PIN attuale errato. Nessun nuovo tentativo automatico.");
            auto json=error(code,message,status);json.pop_back();return json+",\"attemptsRemaining\":"+std::to_string(attempts)+"}";
        }
        if(phase==1 && (status==0x6300 || status==0x6700)) return error(unblock ? "puk_incorrect":"pin_incorrect",unblock ? "PUK non accettato. Tentativi residui non comunicati dalla carta. Nessun nuovo tentativo automatico." : "PIN attuale non accettato. Tentativi residui non comunicati dalla carta. Nessun nuovo tentativo automatico.",status);
        if(status) return error("pin_operation_failed","Operazione non completata. Controllare lettore e carta; nessun tentativo viene ripetuto automaticamente.",status);
        return std::string("{\"ok\":true,\"operation\":\"")+(unblock ? "unblockPin":"changePin")+
            "\",\"message\":\""+(unblock ? "Carta sbloccata e nuovo PIN impostato.":"PIN modificato correttamente.")+" Abbina nuovamente la CIE dalla Home per firmare con le ultime quattro cifre.\"}";
        };
        auto result=perform();result.pop_back();
        result+=",\"pairingInvalidated\":"+std::string(cie_pairing::supported()?"true":"false");
        if(cleanupFailed){result+=",\"cleanupWarning\":\"L’abbinamento è disabilitato, ma la rimozione dall’archivio protetto non è stata completata. Il vecchio prefisso PIN non verrà utilizzato. Ripeti l’abbinamento dalla Home.\",\"cleanupCode\":\"pairing_store_cleanup_failed\"";
          if(cleanupNative)result+=",\"cleanupNativeCode\":"+std::to_string(cleanupNative);}
        return result+"}";
    });
}
char* cie_bridge_change_pin(const char* reader,const char* expected,char* current,char* replacement) {
    return pinOperation(reader,expected,current,replacement,false);
}
char* cie_bridge_unblock_pin(const char* reader,const char* expected,char* puk,char* replacement) {
    return pinOperation(reader,expected,puk,replacement,true);
}

char* cie_bridge_pairings(void){return guarded([]()->std::string{
 try {auto ids=cie_pairing::list();std::string out="{\"ok\":true,\"cards\":[";bool first=true;for(auto& id:ids){if(!first)out+=",";first=false;out+=quote(id);}return out+"]}";}
 catch(...){return error("pairing_store_unavailable","Archivio locale non disponibile. Il PIN completo non viene salvato.");}
});}
char* cie_bridge_web_enroll(const char* reader,const char* card,char* pin){PinGuard secret{pin};return guarded([&]()->std::string{
 if(!webEnrollFn)return error("web_unavailable","Aggiornare il runtime per configurare l’accesso ai siti.");
 if(!reader||!*reader||!card||!cie_pairing::validId(card)||!cie_pin::digits(pin))return error("invalid_pin","Selezionare la CIE e inserire le otto cifre del PIN.");
 uint8_t der[8192]{};uint32_t size=sizeof(der);auto status=webEnrollFn(reader,card,pin,der,&size);
 if(status==0x6983)return error("pin_locked","PIN bloccato. Nessun tentativo automatico.");
 if((status&0xfff0)==0x63c0||status==0x6300)return error("pin_incorrect","PIN non accettato. Nessun tentativo automatico.");
 if(status||!size||size>sizeof(der))return error("web_enrollment_failed","Configurazione non completata. Nessun tentativo viene ripetuto automaticamente.",status);
 try{cie_web_store::write(card,der,size);}
 catch(const std::exception& e){
  if(std::string(e.what())=="web_certificate_conflict")return error("web_certificate_conflict","Questo certificato è già associato a un altro componente di sistema. La configurazione Web di questa applicazione è stata interrotta senza modificare l’associazione esistente. Non occorre ripetere il PIN.");
  return error("web_store_unavailable","PIN verificato ma certificato non salvato nell’archivio locale.");
 }catch(...){return error("web_store_unavailable","PIN verificato ma certificato non salvato nell’archivio locale.");}
 static const char hex[]="0123456789abcdef";std::string encoded;encoded.reserve(size*2);for(uint32_t i=0;i<size;++i){encoded+=hex[der[i]>>4];encoded+=hex[der[i]&15];}
 return "{\"ok\":true,\"card\":"+quote(card)+",\"certificateHex\":"+quote(encoded)+"}";
});}
char* cie_bridge_web_forget(const char* card){return guarded([&]()->std::string{
 if(!card||!cie_pairing::validId(card))return error("web_invalid_id","Selezionare la CIE da rimuovere.");
 try{cie_web_store::erase(card);return "{\"ok\":true}";}catch(...){return error("web_store_unavailable","Rimozione del certificato non completata.");}
});}
char* cie_bridge_web_test(const char* card){return guarded([&]()->std::string{
 if(!card||!cie_pairing::validId(card))return error("web_invalid_id","Selezionare la CIE da provare.");
#if defined(__linux__) && !defined(CIE_WEB_TEST_STORE)
 return error("web_test_requires_firefox","Su Linux la prova di accesso si esegue da Firefox, che richiede il PIN completo di otto cifre. Nessuna prova sulla carta è stata avviata dall’applicazione.");
#else
 try{auto status=cie_web_store::test(card);if(status)return error("web_system_test_failed","Prova del componente Windows non riuscita. Verificare la registrazione del minidriver e la disponibilità della CIE; nessun tentativo automatico.",status);
  return "{\"ok\":true,\"message\":\"Firma della richiesta locale verificata tramite Windows Smart Card KSP. Il login a un sito resta una prova separata.\"}";
 }catch(...){return error("web_system_test_failed","Configurazione Web non disponibile per questo utente.");}
#endif
});}
char* cie_bridge_unpair(const char* card){return guarded([&]()->std::string{
 try{if(!card)return error("pairing_invalid_id","Identificativo CIE mancante");if(*card)cie_pairing::erase(card);else for(auto& id:cie_pairing::list())cie_pairing::erase(id);return "{\"ok\":true}";}
 catch(...){return error("pairing_store_unavailable","Rimozione non completata. Aggiornare l’elenco per controllare gli abbinamenti rimasti.");}
});}
char* cie_bridge_pair(const char* reader,const char* card,char* pin){PinGuard secret{pin};return guarded([&]()->std::string{
 if(!pairAuthFn||!cie_pairing::supported())return error("pairing_unavailable","Abbinamento non disponibile nel runtime.");
 if(!reader||!*reader||!card||!cie_pairing::validId(card)||!cie_pin::digits(pin))return error("invalid_pin","Selezionare una CIE e inserire il PIN completo di otto cifre.");
 cie_pairing::Secret prefix;std::memcpy(prefix.bytes.data(),pin,4);
 try{cie_pairing::prepare();auto ids=cie_pairing::list();if(ids.size()>=256 && std::find(ids.begin(),ids.end(),card)==ids.end())return error("pairing_limit","Rimuovere un abbinamento prima di aggiungerne altri.");}
 catch(...){return error("pairing_store_unavailable","Archivio protetto non disponibile. Nessun tentativo sulla carta.");}
 auto status=pairAuthFn(reader,card,pin);
 if(status==-10)return error("card_changed","La CIE è cambiata. Ripetere il rilevamento.");
 if(status==0x6983)return error("pin_locked","PIN bloccato. Nessun tentativo automatico.");
 if((status&0xfff0)==0x63c0 || status==0x6300)return error("pin_incorrect","PIN non accettato. Nessun tentativo automatico.");
 if(status){
   const bool beforePin=(status<=-29 && status>=-38)||(status<=-51 && status>=-58);
   auto code=beforePin?"pairing_preparation_failed":status<=-41 && status>=-44?"pairing_sod_failed":"pairing_authentication_failed";
   auto message=beforePin?"Preparazione della CIE non completata: nessun PIN inviato. Nessun tentativo automatico.":status<=-41 && status>=-44?"PIN accettato ma verifica dei dati SOD non completata. Abbinamento non salvato.":"Autenticazione non completata. Nessun tentativo automatico.";
   return error(code,message,status);
 }
 try{cie_pairing::write(card,prefix.bytes.data());cie_pairing::acceptFreshPairing(card);}
 catch(...){return error("pairing_store_unavailable","PIN verificato ma abbinamento non salvato nell’archivio protetto.");}
 return "{\"ok\":true,\"message\":\"CIE abbinata a questa applicazione. Per firmare puoi usare le ultime quattro cifre del PIN.\"}";
});}
char* cie_bridge_sign_paired_network(const char* r,const char* c,const char* i,const char* o,const char* f,char* p,const CieNetworkOptions* n){return signDocument(r,c,i,o,f,p,nullptr,n,true);}
char* cie_bridge_sign_pdf_paired_network(const char* r,const char* c,const char* i,const char* o,char* p,const char* image,int32_t page,double left,double top,double width,double height,const CieNetworkOptions* n){CiePdfAppearance a{sizeof(CiePdfAppearance),page,left,top,width,height,image};return signDocument(r,c,i,o,"pdf",p,&a,n,true);}

namespace {
std::string certificateHex(const CieEnrollmentMaterial& m){static const char hex[]="0123456789abcdef";std::string encoded;encoded.reserve(m.certificateLength*2);for(uint32_t i=0;i<m.certificateLength;++i){encoded+=hex[m.certificate[i]>>4];encoded+=hex[m.certificate[i]&15];}return encoded;}
std::string publicCardNumber(const uint8_t* der,uint32_t size){char number[32]{};return certificateCardNumberFn&&!certificateCardNumberFn(der,size,number,sizeof(number))?std::string(number):std::string();}
std::string enrollmentFields(const std::string& card,const CieEnrollmentMaterial& m,bool ready){
 bool provisioned=cie_web_store::provisioned(card,m.certificate,m.certificateLength);
 return "\"card\":"+quote(card)+",\"version\":2,\"fullName\":"+quote(m.fullName)+",\"cardNumber\":"+quote(publicCardNumber(m.certificate,m.certificateLength))+",\"certificateHex\":"+quote(certificateHex(m))+",\"publicDataSaved\":true,\"readyForSigning\":"+(ready?"true":"false")+",\"webProvisioned\":"+(provisioned?"true":"false")+",\"systemComponentAvailable\":"+(cie_web_store::componentAvailable()?"true":"false")+",\"webIdentityObserved\":false";
}
bool paired(const std::string& id){auto ids=cie_pairing::list();return std::find(ids.begin(),ids.end(),id)!=ids.end();}
std::string publishEnrollment(const std::string& id,const CieEnrollmentMaterial& m,bool ready){
 try{cie_web_store::write(id,m.certificate,m.certificateLength);}
 catch(const std::exception& e){return "{\"ok\":true,"+enrollmentFields(id,m,ready)+",\"code\":"+quote(std::string(e.what())=="web_certificate_conflict"?"web_certificate_conflict":"web_store_unavailable")+",\"message\":\"CIE abbinata per firmare. Completa la configurazione per accedere ai siti; non occorre ripetere il PIN.\"}";}
 return "{\"ok\":true,"+enrollmentFields(id,m,ready)+"}";
}
}
char* cie_bridge_certificate_name(const char* hex){return guarded([&]()->std::string{
 if(!hex||!certificateNameFn)return error("certificate_name_unavailable","Nome del titolare non disponibile");
 auto n=std::strlen(hex);if(!n||n>16384||n%2)return error("invalid_certificate","Certificato non valido");
 std::vector<uint8_t> der;der.reserve(n/2);auto digit=[](char c)->int{if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;return -1;};
 for(size_t i=0;i<n;i+=2){auto a=digit(hex[i]),b=digit(hex[i+1]);if(a<0||b<0)return error("invalid_certificate","Certificato non valido");der.push_back(uint8_t(a*16+b));}
 char name[512]{};if(certificateNameFn(der.data(),uint32_t(der.size()),name,sizeof(name)))return error("invalid_certificate","Nome del titolare non disponibile");
 return "{\"ok\":true,\"fullName\":"+quote(name)+",\"cardNumber\":"+quote(publicCardNumber(der.data(),uint32_t(der.size())))+"}";
});}
char* cie_bridge_web_status(void){return guarded([]()->std::string{
 auto out=std::string("{\"ok\":true,\"available\":")+(cie_web_store::componentAvailable()?"true":"false");
#if defined(__linux__) && !defined(CIE_WEB_TEST_STORE)
 out+=",\"provider\":\"linux-firefox-pkcs11\",\"browserRegistrationRequired\":true,\"browserConfigurationVerified\":false,\"fullPinRequired\":true";
#endif
 return out+"}";
});}
char* cie_bridge_enrollments(void){return guarded([]()->std::string{
 auto blocked=cie_pairing::invalidatedCards();std::string invalidations=",\"invalidatedCards\":[";bool firstBlocked=true;
 for(const auto& id:blocked){if(!firstBlocked)invalidations+=",";firstBlocked=false;invalidations+=quote(id);}invalidations+="]";
 try{auto signedIds=cie_pairing::list(),ids=cie_pairing::listPublic();ids.insert(ids.end(),signedIds.begin(),signedIds.end());auto webIds=cie_web_store::list();ids.insert(ids.end(),webIds.begin(),webIds.end());std::sort(ids.begin(),ids.end());ids.erase(std::unique(ids.begin(),ids.end()),ids.end());
  std::string out="{\"ok\":true,\"storage\":\"file-cache-v3\",\"records\":[";bool first=true;
  for(const auto& id:ids){if(std::find(blocked.begin(),blocked.end(),id)!=blocked.end())continue;if(!first)out+=",";first=false;bool ready=std::find(signedIds.begin(),signedIds.end(),id)!=signedIds.end();std::vector<uint8_t> bytes;
   try{bytes=cie_pairing::readPublic(id);}catch(...){out+="{\"card\":"+quote(id)+",\"version\":0,\"readyForSigning\":false,\"publicDataSaved\":false,\"code\":\"pairing_cache_invalid\"}";continue;}
   if(bytes.empty()){
    std::string name,number;try{auto der=cie_web_store::read(id);char text[512]{};if(certificateNameFn&&!der.empty()&&!certificateNameFn(der.data(),uint32_t(der.size()),text,sizeof(text)))name=text;number=publicCardNumber(der.data(),uint32_t(der.size()));}catch(...){}
    out+="{\"card\":"+quote(id)+",\"fullName\":"+quote(name)+",\"cardNumber\":"+quote(number)+",\"version\":1,\"readyForSigning\":"+(ready?"true":"false")+",\"publicDataSaved\":false}";continue;}
   try{auto material=cie::decodeEnrollment(bytes);out+="{"+enrollmentFields(id,material,ready)+"}";}
   catch(...){out+="{\"card\":"+quote(id)+",\"version\":0,\"readyForSigning\":"+(ready?"true":"false")+",\"publicDataSaved\":false,\"code\":\"enrollment_invalid_record\"}";}
  }return out+"]"+invalidations+"}";
 }catch(...){auto out=error("pairing_store_unavailable","Archivio protetto non leggibile. Gli abbinamenti disabilitati dopo un cambio PIN restano inutilizzabili.");out.pop_back();return out+invalidations+"}";}
});}
char* cie_bridge_enroll(const char* reader,const char* card,char* pin){PinGuard guard{pin};return guarded([&]()->std::string{
 if(!enrollFn||!cie_pairing::supported())return error("enrollment_unavailable","Aggiornare il runtime per l’abbinamento unico. Nessun PIN inviato.");
 if(!reader||!*reader||!card||!cie_pairing::validId(card)||!cie_pin::digits(pin))return error("invalid_pin","Selezionare una CIE e inserire le otto cifre del PIN.");
 cie_pairing::Secret prefix;std::memcpy(prefix.bytes.data(),pin,4);bool previous=false;
 try{cie_pairing::prepare();auto ids=cie_pairing::list(),publicIds=cie_pairing::listPublic();previous=std::find(ids.begin(),ids.end(),card)!=ids.end();std::set<std::string> all(ids.begin(),ids.end());all.insert(publicIds.begin(),publicIds.end());if(all.size()>=256&&!all.count(card))return error("pairing_limit","Rimuovere una CIE prima di aggiungerne un’altra.");(void)cie_pairing::readPublic(card);}
 catch(...){return error("pairing_store_unavailable","Archivio protetto non leggibile. Nessun PIN inviato.");}
 CieEnrollmentMaterial m{};m.size=sizeof(m);auto status=enrollFn(reader,card,pin,&m);
 if(status==-10)return error("card_changed","La carta è cambiata. Nessun nuovo tentativo automatico.");
 if(status==0x6983)return error("pin_locked","PIN bloccato. Nessun tentativo automatico.");
 if((status&0xfff0)==0x63c0||status==0x6300)return error("pin_incorrect","PIN non accettato. Nessun tentativo automatico.");
 if(status)return error("enrollment_authentication_failed","Abbinamento non completato. Nessuna autenticazione viene ripetuta automaticamente.",status);
 try{cie_pairing::writePublic(card,cie::encodeEnrollment(m));}
 catch(...){return error("enrollment_public_store_failed","PIN verificato, ma dati pubblici non salvati. L’abbinamento precedente è stato conservato; non è stato eseguito un nuovo tentativo.");}
 try{cie_pairing::write(card,prefix.bytes.data());cie_pairing::acceptFreshPairing(card);}
 catch(...){return "{\"ok\":false,"+enrollmentFields(card,m,previous)+",\"code\":\"pairing_store_unavailable\",\"message\":\"Dati pubblici verificati e salvati, ma abbinamento per la firma non completato. Nessun PIN conservato per riprovare.\"}";}
 return publishEnrollment(card,m,true);
});}
char* cie_bridge_complete_enrollment(const char* card){return guarded([&]()->std::string{
 if(!card||!cie_pairing::validId(card))return error("pairing_invalid_id","Selezionare la CIE.");
 try{if(cie_pairing::invalidated(card))return error("enrollment_read_required","Dopo il cambio PIN occorre abbinare nuovamente la CIE dalla Home con il PIN completo.");auto bytes=cie_pairing::readPublic(card);if(bytes.empty())return error("enrollment_read_required","Per questa CIE serve completare l’abbinamento con il PIN completo, una sola volta.");return publishEnrollment(card,cie::decodeEnrollment(bytes),paired(card));}
 catch(...){return error("pairing_store_unavailable","Configurazione non completata. Nessun tentativo sulla carta.");}
});}
char* cie_bridge_forget_enrollment(const char* card){return guarded([&]()->std::string{
 if(!card||!cie_pairing::validId(card))return error("pairing_invalid_id","Selezionare la CIE da rimuovere.");
 const char* stage="web_certificate";
 auto failure=[&](int64_t native=0){
  auto out=error("enrollment_removal_incomplete","Rimozione non completata. Verifica che la cartella dati dell’applicazione sia accessibile e premi Riprova rimozione. Il PIN della carta non serve.",native);
  out.pop_back();return out+",\"removalStage\":"+quote(stage)+"}";
 };
 try{cie_web_store::erase(card);stage="pairing_cache";cie_pairing::eraseRecord(card);return "{\"ok\":true}";}
 catch(const cie_pairing::StoreError& e){return failure(e.nativeCode);}
 catch(...){return failure();}
});}
