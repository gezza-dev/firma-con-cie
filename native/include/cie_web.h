// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef CIE_WEB_NOEXPORT
#define CIE_WEB_API
#elif defined(_WIN32)
#define CIE_WEB_API __declspec(dllexport)
#else
#define CIE_WEB_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Independent C ABI for OS token providers. Caller owns the transaction and
// transport lifetime. No PC/SC connection, reset, PIN dialog or network here.
typedef struct CieWebSession CieWebSession;
typedef int32_t (*CieWebTransmit)(void*,const uint8_t*,uint32_t,uint8_t*,uint32_t*);
enum { CIE_WEB_OK=0,CIE_WEB_ARGUMENT=-1,CIE_WEB_TRANSPORT=-2,
 CIE_WEB_CARD=-3,CIE_WEB_AUTH_REQUIRED=-4,CIE_WEB_STATE=-5,
 CIE_WEB_BUFFER=-6,CIE_WEB_ALGORITHM=-7,CIE_WEB_IDENTITY=-8 };
CIE_WEB_API uint32_t cie_web_abi_version(void);
// Optional expected ID binds the operation to the selected card. Open does
// not send VERIFY. A transport failure is terminal, never automatically replayed.
CIE_WEB_API int32_t cie_web_open(const uint8_t* atr,uint32_t atr_size,
 CieWebTransmit transmit,void* context,const char* expected_id,CieWebSession** result);
CIE_WEB_API void cie_web_close(CieWebSession*);
CIE_WEB_API int32_t cie_web_identifier(CieWebSession*,char* output,uint32_t* size);
// Provisioned public DER from an authenticated enrollment. Bound again to the
// current card's signed SOD. Does not authenticate or load any PIN fragment.
CIE_WEB_API int32_t cie_web_set_certificate(CieWebSession*,const uint8_t* der,uint32_t size);
// Public DER, SOD-checked; never exposes a PIN or key. If card policy requires
// authentication this returns CARD; adapters must not invent a certificate.
CIE_WEB_API int32_t cie_web_certificate(CieWebSession*,uint8_t* output,uint32_t* size);
// Exactly eight ASCII digits, once per session. Input is always wiped. A new
// user action/new session is necessary after any failed attempt. 63Cx/6983 are
// returned verbatim; no retries and no PIN/PUK mutation entry points exist.
CIE_WEB_API int32_t cie_web_authenticate(CieWebSession*,char* pin,uint32_t size);
// Strict SHA-256/384/512 DER DigestInfo only; RSA PKCS#1 v1.5, big endian.
// Size queries and short buffers never invoke the private key operation.
CIE_WEB_API int32_t cie_web_sign(CieWebSession*,const uint8_t* digest_info,
 uint32_t length,uint8_t* signature,uint32_t* size);
#ifdef __cplusplus
}
#endif
