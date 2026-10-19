//
//  VerificaConCIE.cpp
//  cie-pkcs11
//
//

#include "VerificaConCIE.h"
#include "../PKCS11/PKCS11Functions.h"
#include "../LOGGER/Logger.h"
#include <cstring>
using CieIDLogger::Logger;

extern "C" {
    CK_RV CK_ENTRY verificaConCIE(const char* inFilePath, const char* proxyAddress, int proxyPort, const char* usrPass);
    CK_RV CK_ENTRY estraiP7m(const char* inFilePath, const char* outFilePath);
    CK_RV CK_ENTRY getVerifyInfo(int index, struct verifyInfo_t* vInfos);
}

VERIFY_RESULT verifyResult;

CK_RV CK_ENTRY getDocumentTimestampValidation(CIE_TEMPORAL_VALIDATION* information)
{
    if (!information || information->size != sizeof(*information) || verifyResult.nErrorCode) return CKR_ARGUMENTS_BAD;
    *information=verifyResult.verifyInfo.documentTimestamps;
    return CKR_OK;
}

CK_RV CK_ENTRY getTemporalValidation(int index, CIE_TEMPORAL_VALIDATION* information)
{
    if (!information || information->size != sizeof(*information) || index < 0 || index >= getNumberOfSign())
        return CKR_ARGUMENTS_BAD;
    *information = verifyResult.verifyInfo.pSignerInfos->pSignerInfo[index].temporalValidation;
    return CKR_OK;
}

CK_RV CK_ENTRY getCertificateValidation(int index, CIE_CERTIFICATE_VALIDATION* information)
{
    if (!information || information->size != sizeof(*information) || index < 0 || index >= getNumberOfSign())
        return CKR_ARGUMENTS_BAD;
    *information = verifyResult.verifyInfo.pSignerInfos->pSignerInfo[index].certificateValidation;
    return CKR_OK;
}

CK_RV CK_ENTRY getNumberOfSign()
{
    if (verifyResult.nErrorCode || !verifyResult.verifyInfo.pSignerInfos) return 0;
    return (CK_RV)verifyResult.verifyInfo.pSignerInfos->nCount;
}

CK_RV CK_ENTRY getVerifyInfo(int index, struct verifyInfo_t* vInfos)
{
    if (!vInfos) return CKR_ARGUMENTS_BAD;
    *vInfos = {};
    vInfos->CertRevocStatus = REVOCATION_STATUS_UNKNOWN;
    if (index >= 0 && index < getNumberOfSign())
    {
        SIGNER_INFO tmpSignerInfo = (verifyResult.verifyInfo.pSignerInfos->pSignerInfo)[index];// +(index * sizeof(SIGNER_INFO)));
        strcpy(vInfos->name, tmpSignerInfo.szGIVENNAME);
        strcpy(vInfos->surname, tmpSignerInfo.szSURNAME);
        strcpy(vInfos->cn, tmpSignerInfo.szCN);
        strcpy(vInfos->cadn, tmpSignerInfo.szCADN);
        strcpy(vInfos->signingTime, tmpSignerInfo.szSigningTime);
        if (tmpSignerInfo.pRevocationInfo)
            vInfos->CertRevocStatus = tmpSignerInfo.pRevocationInfo->nRevocationStatus;
        vInfos->isCertValid = tmpSignerInfo.bitmask >= 0 &&
            (tmpSignerInfo.bitmask & VERIFIED_CERT_VALIDITY) == VERIFIED_CERT_VALIDITY;
        vInfos->isSignValid = tmpSignerInfo.bitmask >= 0 &&
            (tmpSignerInfo.bitmask & VERIFIED_SIGNATURE) == VERIFIED_SIGNATURE;
        return CKR_OK;
    }
    return CKR_ARGUMENTS_BAD;
}

CK_RV CK_ENTRY verificaConCIE(const char* inFilePath, const char* proxyAddress, int proxyPort, const char* usrPass)
{
    disigon_verify_cleanup_result(&verifyResult);
    verifyResult = {};
    CIEVerify verifier;
    long result = verifier.verify(inFilePath, &verifyResult, proxyAddress, proxyPort, usrPass);
    if (result) verifyResult.nErrorCode = result;

    if (verifyResult.nErrorCode == 0)
    {
        printf("verificaConCIE OK");
        
        if(verifyResult.verifyInfo.pSignerInfos != NULL)
            return (CK_RV)verifyResult.verifyInfo.pSignerInfos->nCount;
        
        return 0;
    }
    else
    {
        printf("Errore nella verifica: %lu\n", verifyResult.nErrorCode);
        LOG_ERROR("verificaConCIE - Errore nella verifica: %lu\n", verifyResult.nErrorCode);
        return verifyResult.nErrorCode;
    }
}

CK_RV CK_ENTRY estraiP7m(const char* inFilePath, const char* outFilePath) {

    CIEVerify verifier;

    long res = verifier.get_file_from_p7m(inFilePath, outFilePath);

    return res;

}
