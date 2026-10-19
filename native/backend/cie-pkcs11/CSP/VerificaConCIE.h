//
//  VerificaConCIE.h
//  cie-pkcs11
//
//  Copyright © 2021 IPZS. All rights reserved.
//

#ifndef VerificaConCIE_h
#define VerificaConCIE_h

#include <stdio.h>
#include "../PKCS11/cryptoki.h"
#include "../Sign/CIEVerify.h"

//typedef CK_RV (*verificaConCIEfn)(const char* inFilePath, verifyInfos_t* vInfos);
typedef CK_RV (*verificaConCIEfn)(const char* inFilePath, const char* proxyAddress, int proxyPort, const char* usrPass);

typedef CK_RV (*getVerifyInfofn)(int index, verifyInfo_t* vInfo);

extern "C" {
CK_RV verificaConCIE(const char* inFilePath, const char* proxyAddress, int proxyPort, const char* usrPass);
CK_RV getVerifyInfo(int index, verifyInfo_t* vInfo);
CK_RV getNumberOfSign();
CK_RV getDocumentTimestampValidation(CIE_TEMPORAL_VALIDATION* information);
CK_RV getTemporalValidation(int index, CIE_TEMPORAL_VALIDATION* information);
CK_RV getCertificateValidation(int index, CIE_CERTIFICATE_VALIDATION* information);
}

typedef CK_RV (*estraiP7mfn)(const char* inFilePath, const char* outFilePath);


#endif /* VerificaConCIE_h */
