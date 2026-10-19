#include "TSAClient.h"


#include <stdio.h>
#include <string.h>
#include "ASN1/TimeStampResponse.h"
#include "ASN1/TimeStampRequest.h"
#include "ASN1/TimeStampToken.h"
#include "Base64.h"
#include "UUCLogger.h"
#include "Native/HttpClient.h"

USE_LOG;

#ifdef __ANDROID__
long  GetTSAResponse(char* szTsaURL, char* szTsaUsername, char* szTsaPassword, UUCByteArray& request, UUCByteArray& response);
#else
#include "curl/curl.h"
#endif

static size_t WriteCallback(void *contents, size_t size, size_t nmemb, void *userp);

CTSAClient::CTSAClient(void)
{
	m_szTSAUsername[0] = 0;
    m_szTSAPassword[0] = 0;
    m_szTSAUrl[0] = 0;
}

CTSAClient::~CTSAClient(void)
{
}

void CTSAClient::SetTSAUrl(const char* szUrl)
{
	strcpy(m_szTSAUrl,szUrl);
}

void CTSAClient::SetCredential(const char* szUsername, const char* szPassword)
{
	strcpy(m_szTSAUsername, (char*)szUsername);
	strcpy(m_szTSAPassword,(char*)szPassword);
}

void CTSAClient::SetUsername(const char* szUsername)
{
	strcpy(m_szTSAUsername, (char*)szUsername);
}

void CTSAClient::SetPassword(const char* szPassword)
{
	strcpy(m_szTSAPassword , (char*)szPassword);
}

long CTSAClient::GetTimeStampToken(UUCByteArray& digest, const char* szPolicyID, CTimeStampToken** ppTimeStampToken)
{
	CASN1Integer nounce(1);
	CTimeStampRequest request(szSHA256OID, digest, szPolicyID, nounce);
	//CTimeStampRequest request(szSHA1OID, digest, szPolicyID, nounce);

	UUCByteArray tsaRequest;
	request.toByteArray(tsaRequest);

	UUCByteArray tsdata;

#ifdef __ANDROID__

	long nRet = GetTSAResponse(m_szTSAUrl, m_szTSAUsername, m_szTSAPassword, tsaRequest, tsdata);
	if(nRet != 0)
		return nRet;
#else

    cie::HttpOptions options;
    options.username = m_szTSAUsername;
    if (m_szTSAUsername[0]) options.password = m_szTSAPassword;
    std::vector<unsigned char> requestBody(tsaRequest.getContent(), tsaRequest.getContent() + tsaRequest.getLength());
    auto reply = cie::httpRequest(m_szTSAUrl, requestBody, "application/timestamp-query", options, 1024 * 1024);
    if (reply.error != CURLE_OK) return reply.error;
    if (reply.body.empty()) return -1;
    tsdata.append(reply.body.data(), reply.body.size());

#endif  // __ANDROID__

	try
	{
		CTimeStampResponse tsResponse((BYTE*)tsdata.getContent(), (int)tsdata.getLength());

		CPKIStatusInfo statusInfo(tsResponse.getPKIStatusInfo());

		if(statusInfo.getStatus().getIntValue() == 0)
		{
			*ppTimeStampToken = new CTimeStampToken(tsResponse.getTimeStampToken());
		}
		else
		{
			LOG_ERR((0, "TSACLient", "CPKIStatusInfo error: %x", statusInfo.getStatus().getIntValue()));

			*ppTimeStampToken = NULL;
		}
	}
	catch(...)
	{
		*ppTimeStampToken = NULL;
	}

	if(*ppTimeStampToken == NULL)
		return -1;

	return 0;
}

static size_t WriteCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
	UUCByteArray* pData = (UUCByteArray*)userp;

	size_t realsize = size * nmemb;
	pData->append((BYTE*)contents, realsize);

	/*
	CTimeStampToken** ppTimeStampToken = (CTimeStampToken**)userp;

	size_t realsize = size * nmemb;

	CTimeStampResponse tsResponse((BYTE*)contents, (int)realsize);

	CPKIStatusInfo statusInfo(tsResponse.getPKIStatusInfo());

	if(statusInfo.getStatus().getIntValue() == 0)
	{
		*ppTimeStampToken = new CTimeStampToken(tsResponse.getTimeStampToken());
	}
	else
	{
		*ppTimeStampToken = NULL;
	}
*/
	return realsize;
}




