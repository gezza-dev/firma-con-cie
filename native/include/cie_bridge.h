// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stdint.h>
#include "cie_document_types.h"
#include "cie_network_types.h"
#ifdef _WIN32
#define CIE_EXPORT __declspec(dllexport)
#else
#define CIE_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Owned UTF-8 JSON results. Every non-null result must be freed by cie_bridge_free.
// All calls are serialized; no native exceptions or C++ objects cross this ABI.
CIE_EXPORT uint32_t cie_bridge_abi_version(void);
CIE_EXPORT char* cie_bridge_web_enroll(const char* reader,const char* card,char* full_pin);
CIE_EXPORT char* cie_bridge_web_forget(const char* card);
CIE_EXPORT char* cie_bridge_web_test(const char* card);
CIE_EXPORT char* cie_bridge_load(const char* middleware_path, const char* card_adapter_path);
CIE_EXPORT char* cie_bridge_detect(void);
// Background observation is read-only and never waits for an occupied card.
CIE_EXPORT char* cie_bridge_observe(void);
// v2: one VERIFY, SOD-bound public material, protected prefix, recoverable OS phase.
CIE_EXPORT char* cie_bridge_enroll(const char*,const char*,char* full_pin);
CIE_EXPORT char* cie_bridge_enrollments(void);
CIE_EXPORT char* cie_bridge_complete_enrollment(const char* card);
CIE_EXPORT char* cie_bridge_forget_enrollment(const char* card);
CIE_EXPORT char* cie_bridge_web_status(void);
CIE_EXPORT char* cie_bridge_verify(const char* input_path);
CIE_EXPORT char* cie_bridge_verify_network(const char* input_path,const CieNetworkOptions* network);
CIE_EXPORT char* cie_bridge_network_probe(const CieNetworkOptions* network);
CIE_EXPORT char* cie_bridge_sign_network(const char* reader,const char* expected_card,
 const char* input_path,const char* output_path,const char* format,char* pin,const CieNetworkOptions* network);
CIE_EXPORT char* cie_bridge_sign_pdf_network(const char* reader,const char* expected_card,
 const char* input_path,const char* output_path,char* pin,const char* image_path,
 int32_t page,double left,double top,double width,double height,const CieNetworkOptions* network);
// Explicit save-dialog replacement; old signing APIs keep no-overwrite behavior.
CIE_EXPORT char* cie_bridge_sign_network_replace(const char* reader,const char* expected_card,
 const char* input_path,const char* output_path,const char* format,char* pin,const CieNetworkOptions* network);
CIE_EXPORT char* cie_bridge_sign_pdf_network_replace(const char* reader,const char* expected_card,
 const char* input_path,const char* output_path,char* pin,const char* image_path,
 int32_t page,double left,double top,double width,double height,const CieNetworkOptions* network);
CIE_EXPORT char* cie_bridge_sign_paired_network_replace(const char*,const char*,const char*,const char*,const char*,char*,const CieNetworkOptions*);
CIE_EXPORT char* cie_bridge_sign_pdf_paired_network_replace(const char*,const char*,const char*,const char*,char*,const char*,int32_t,double,double,double,double,const CieNetworkOptions*);
// Read-only format eligibility: parses PDF/CMS, never accesses a card or network.
// Parse public certificate subject only; no card, trust promotion or PIN.
CIE_EXPORT char* cie_bridge_certificate_name(const char* certificate_hex);
CIE_EXPORT char* cie_bridge_signing_info(const char* input_path);
CIE_EXPORT char* cie_bridge_pdf_info(const char* input_path,int32_t page);
CIE_EXPORT char* cie_bridge_extract(const char* input_path,const char* output_path);
CIE_EXPORT char* cie_bridge_sign_pdf(const char* reader,const char* expected_card,
    const char* input_path,const char* output_path,char* pin,const char* image_path,
    int32_t page,double left,double top,double width,double height);
// Eight digits, one attempt only. The mutable PIN buffer is wiped before returning.
CIE_EXPORT char* cie_bridge_sign(const char* reader, const char* expected_card,
    const char* input_path, const char* output_path, const char* format, char* pin);
// Private prototype enrollment. Prefix stays exclusively in native protected storage.
CIE_EXPORT char* cie_bridge_pair(const char* reader,const char* expected_card,char* full_pin);
CIE_EXPORT char* cie_bridge_pairings(void);
CIE_EXPORT char* cie_bridge_unpair(const char* card); // empty string removes all prototype records
CIE_EXPORT char* cie_bridge_sign_paired_network(const char*,const char*,const char*,const char*,const char*,char*,const CieNetworkOptions*);
CIE_EXPORT char* cie_bridge_sign_pdf_paired_network(const char*,const char*,const char*,const char*,char*,const char*,int32_t,double,double,double,double,const CieNetworkOptions*);
CIE_EXPORT void cie_bridge_free(char* result);
// Additive ABI v1 capabilities. Eight-digit secrets are mutable and wiped on
// every exit. Exactly one authentication and at most one mutation; never retry.
CIE_EXPORT char* cie_bridge_change_pin(const char* reader,const char* expected_card,char* current,char* replacement);
CIE_EXPORT char* cie_bridge_unblock_pin(const char* reader,const char* expected_card,char* puk,char* replacement);
#ifdef __cplusplus
}
#endif
