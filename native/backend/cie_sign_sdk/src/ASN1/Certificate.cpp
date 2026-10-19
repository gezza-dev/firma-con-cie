#include "../Native/RsaRecovery.h"
#include <memory>
#include <vector>
// Certificate.cpp: implementation of the CCertificate class.
//
//////////////////////////////////////////////////////////////////////


#include "Certificate.h"
#include "ASN1Octetstring.h"
#include "../Native/Digest.h"
#include "OCSPRequest.h"
#include "ASN1OptionalField.h"
#include "Crl.h"
#include "Asn1Errors.h"
#include "RSAPublicKey.h"
#include "../Native/Digest.h"
#include "DigestInfo.h"
#include <sys/types.h>
#include <time.h>
#include "RSAPublicKey.h"
#include "Base64.h"
#include <curl/curl.h>
#include "LdapCrl.h"
#include "UUCLogger.h"
#include "CertStore.h"
#include "ASN1Setof.h"
#include "../Native/Revocation.h"
#include "../Native/CertificateTrust.h"
#include <openssl/bio.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>

#define PROXY_AUTHENTICATION_REQUIRED	407

static size_t WriteCallback(void *contents, size_t size, size_t nmemb, void *userp);
long HTTPRequest(UUCByteArray& data, const char* szUrl, const char* szContentType, UUCByteArray& response);

extern char g_szVerifyProxy[MAX_PATH];
extern char* g_szVerifyProxyUsrPass;
extern int g_nVerifyProxyPort;

USE_LOG;

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

CCertificate* CCertificate::createCertificate(UUCByteArray& contentArray)
{
	const BYTE* content = contentArray.getContent();
	int len = contentArray.getLength();
	//UUCByteArray c;

	if(content[0] != 0x30) // base64
	{
		char* szBase64Content;
		char* szContent = new char[len + 1];
		char* szEncoded = new char[len + 1];

		memcpy(szContent, content, len);
		szContent[len] = 0;
		char* pos = strstr(szContent, "--");

		if(pos != NULL) // header PEM da eliminare
		{
			szBase64Content = strtok(szContent, "\r\n");
			szBase64Content = strtok(NULL, "----");
		}
		else
		{
			szBase64Content = szContent;
		}

		strcpy(szEncoded, "");

		char* szPart = strtok(szBase64Content, "\r\n");
		while(szPart)
		{
			strcat(szEncoded, szPart);
			szPart = strtok(NULL, "\r\n");
		}

		size_t decLen = base64_decoded_size(strlen(szEncoded));
		char* szDecoded = base64_decode(szEncoded);

		if(!(szDecoded[0] == 0x30 && (szDecoded[1] & 0x80)))
		{
			free(szDecoded);
			//LOG_ERR((0, "CSignedDocument", "No X509 Cert"));
			throw -6;
		}

		UUCBufferedReader reader((BYTE*)szDecoded, decLen);

		delete szContent;

		CCertificate* pCert = new CCertificate(reader);

		free(szDecoded);

		return pCert;

	}
	else
	{
//		if(!(content[0] == 0x30 && (content[1] & 0x80)))
//		{
//			//LOG_ERR((0, "CSignedDocument", "No X509 Cert"));
//			throw -6;
//		}

		//c.append(content, len);
		UUCBufferedReader reader((BYTE*)content, len);
		//c.append();

		//delete raw;
		//delete szContent;

		return new CCertificate(reader);
	}


}

CCertificate::CCertificate(const BYTE* value, long len)
: CASN1Sequence(value, len)
{

}

CCertificate::CCertificate(UUCBufferedReader& reader)
:CASN1Sequence(reader)
{

}

/*
CCertificate::CCertificate(const CCertificateInfo& certInfo, const CAlgorithmIdentifier& algoId, const CASN1BitString& signature)
{
	addElement(new CCertificateInfo(certInfo));
	addElement(new CAlgorithmIdentifier(algoId));
	addElement(new CASN1BitString(signature));
}
*/

CCertificate::CCertificate(const CASN1Object& cert)
: CASN1Sequence(cert)
{

}

CCertificate::~CCertificate()
{

}

CCertificateInfo CCertificate::getCertificateInfo()
{
	return elementAt(0);
}

CAlgorithmIdentifier CCertificate::getAlgorithmIdentifier()
{
	return elementAt(1);
}

CName CCertificate::getIssuer()
{
	return getCertificateInfo().getIssuer();
}

CName CCertificate::getSubject()
{
	return getCertificateInfo().getSubject();
}

CASN1Integer CCertificate::getSerialNumber()
{
	return getCertificateInfo().getSerialNumber();
}

CASN1UTCTime CCertificate::getExpiration()
{
	return getCertificateInfo().getExpiration();
}

CASN1UTCTime CCertificate::getFrom()
{
	return getCertificateInfo().getFrom();
}


CASN1Sequence CCertificate::getExtensions()
{
	return getCertificateInfo().getExtensions();
}

CASN1Sequence CCertificate::getQCStatements()
{
	return getExtension(CASN1ObjectIdentifier("1.3.6.1.5.5.7.1.3"));
}

bool CCertificate::isNonRepudiation()
{
	CASN1Sequence keyUsage(getExtension(CASN1ObjectIdentifier("2.5.29.15")));
	int n = keyUsage.size();
	if(n == 0) // not found
		return false;


	CASN1OctetString octetString(keyUsage.elementAt(n-1));

	UUCByteArray content;

	// content
	if(octetString.getTag() == 0x24) // contructed octet string
	{
		CASN1Sequence contentArray(octetString);
		int size = contentArray.size();
		for(int i = 0; i < size; i++)
		{
			CASN1OctetString part(contentArray.elementAt(i));
			content.append(part.getValue()->getContent(), part.getLength());
		}
	}
	else
	{
		content.append(octetString.getValue()->getContent(), octetString.getLength());
	}

	UUCBufferedReader reader(content);
	CASN1BitString val(reader);

	const BYTE* pKeyUsageFlags = val.getValue()->getContent();
	BYTE unusedbits = pKeyUsageFlags[0];
	BYTE flags = pKeyUsageFlags[1];
	if(unusedbits < 7)
	{
		if((flags & 0x40) == 0x40)// non repudiation and digital signature
			return true;
	}

	return false;
}

bool CCertificate::isQualified()
{

	CASN1Sequence keyUsage(getExtension(CASN1ObjectIdentifier("2.5.29.15")));
	if(keyUsage.size() == 0) // not found
		return false;


	CASN1OctetString val(keyUsage.elementAt(1));
	const BYTE* pKeyUsageFlags = val.getValue()->getContent();
	if(!(pKeyUsageFlags[0] & 0x01)) // non repudiation
		return false;

	CASN1Sequence qcStatement(getExtension(CASN1ObjectIdentifier("1.3.6.1.5.5.7.1.3")));
	if(qcStatement.size() == 0) // not found
		return false;

	/* spostato in basso nell'apposito metodo
	 CAlgorithmIdentifier sha256Algo(szSHA256OID);
	CAlgorithmIdentifier digestAlgo(elementAt(1));
	if(!(digestAlgo.elementAt(0) == sha256Algo.elementAt(0)))
		return false;
	*/

	return true;
}

bool CCertificate::isSHA256()
{

	CAlgorithmIdentifier sha256Algo(szSHA256OID);
	CAlgorithmIdentifier digestAlgo(elementAt(1));
	if(!(digestAlgo.elementAt(0) == sha256Algo.elementAt(0)))
		return false;

	return true;
}
bool CCertificate::isValid()
{
	char szTime[20];
	time_t now = time(NULL);
	struct tm utc;
#ifdef CIE_LEGACY_WINDOWS
    gmtime_s(&utc, &now);
#else
#ifdef _WIN32
    gmtime_s(&utc, &now);
#else
    gmtime_r(&now, &utc);
#endif
#endif
	strftime(szTime, 20, "%y%m%d%H%M%SZ", &utc);

	return isValid(szTime);
}

bool CCertificate::isValid(const char* szDateTime)
{
	if(!szDateTime)
		return isValid();

	CASN1UTCTime utcnow(szDateTime);

	CASN1UTCTime expiration(getExpiration());

	BYTE* btExpiration;

	if(expiration.getValue()->getLength() > 13)
	{
		btExpiration = (BYTE*)expiration.getValue()->getContent() + expiration.getValue()->getLength() - 13;
	}
	else
	{
		btExpiration = (BYTE*)expiration.getValue()->getContent();
	}

	if(memcmp(utcnow.getValue()->getContent(), btExpiration, 13) > 0)
		return false;

	CASN1UTCTime from(getFrom());

	BYTE* btFrom;

	if(from.getValue()->getLength() > 13)
	{
		btFrom = (BYTE*)from.getValue()->getContent() + from.getValue()->getLength() - 13;
	}
	else
	{
		btFrom = (BYTE*)from.getValue()->getContent();
	}

	if(memcmp(utcnow.getValue()->getContent(), btFrom, 13) < 0)
		return false;

	return true;
}


CASN1Sequence CCertificate::getExtension(const CASN1ObjectIdentifier& oid)
{
	CASN1Sequence certExtensions = getExtensions();
	CASN1Sequence extensions = certExtensions.elementAt(0);
	CASN1Sequence requestedExtension;
	int count = extensions.size();
	for(int i = 0; i < count; i++)
	{
		CASN1Sequence extension = extensions.elementAt(i);
		//int n = extension.size();
		//const char* szHex = ((UUCByteArray*)(extension.getValue()))->toHexString();
		CASN1ObjectIdentifier extoid = extension.elementAt(0);
		if(extoid.equals(oid))
		{
			return extension;

		}
	}

	return requestedExtension;
}


CASN1Sequence CCertificate::getCertificatePolicies()
{
	CASN1Sequence certPolicies(getExtension(szCertificatePolicies));

	if(certPolicies.size() > 0)
	{
		CASN1OctetString val(certPolicies.elementAt(1));

		UUCBufferedReader reader(*val.getValue());
		return CASN1Sequence(reader);
	}
	else
	{
		return CASN1Sequence();
	}
}

CASN1OctetString CCertificate::getAuthorithyKeyIdentifier()
{
	CASN1Sequence keyIdentifier(getExtension(szAuthorityKeyIdentifier));

	CASN1OctetString val(keyIdentifier.elementAt(1));

	UUCBufferedReader reader(*val.getValue());
	return CASN1Sequence(reader);
}


CASN1OctetString CCertificate::getSubjectKeyIdentifier()
{

    CASN1Sequence keyIdentifier = getExtension(szSubjectKeyIdentifier);

    if(keyIdentifier.size() > 0)
    {
        CASN1OctetString val(keyIdentifier.elementAt(1));
        return val;
    }
    else
    {
        CASN1OctetString val("");
        return val;
    }
}

/*
 A.1 OCSP over HTTP


 This section describes the formatting that will be done to the
 request and response to support HTTP.

 A.1.1 Request


 HTTP based OCSP requests can use either the GET or the POST method to
 submit their requests. To enable HTTP caching, small requests (that
 after encoding are less than 255 bytes), MAY be submitted using GET.
 If HTTP caching is not important, or the request is greater than 255
 bytes, the request SHOULD be submitted using POST.  Where privacy is
 a requirement, OCSP transactions exchanged using HTTP MAY be
 protected using either TLS/SSL or some other lower layer protocol.

 An OCSP request using the GET method is constructed as follows:

 GET {url}/{url-encoding of base-64 encoding of the DER encoding of
 the OCSPRequest}

 where {url} may be derived from the value of AuthorityInfoAccess or
 other local configuration of the OCSP client.

 An OCSP request using the POST method is constructed as follows: The
 Content-Type header has the value "application/ocsp-request" while
 the body of the message is the binary value of the DER encoding of
 the OCSPRequest.

 A.1.2 Response


 An HTTP-based OCSP response is composed of the appropriate HTTP
 headers, followed by the binary value of the DER encoding of the
 OCSPResponse. The Content-Type header has the value
 "application/ocsp-response". The Content-Length header SHOULD specify
 the length of the response. Other HTTP headers MAY be present and MAY
 be ignored if not understood by the requestor.
*/

int CCertificate::verifyStatus(REVOCATION_INFO* pRevocationInfo)
{
	return verifyStatus(NULL, pRevocationInfo);
}

int CCertificate::verifyStatus(const char* szTime, REVOCATION_INFO* information)
{
    return verifyStatus(szTime, information, nullptr);
}

int CCertificate::verifyStatus(const char*, REVOCATION_INFO* information, CASN1SetOf* certificates)
{
    UUCByteArray encoded;
    toByteArray(encoded);
    cie::CertificateBytes target(encoded.getContent(), encoded.getContent() + encoded.getLength());
    std::vector<cie::CertificateBytes> candidates;
    if (certificates) {
        for (int i = 0; i < certificates->size() && i < 64; ++i) {
            UUCByteArray value;
            certificates->elementAt(i).toByteArray(value);
            candidates.emplace_back(value.getContent(), value.getContent() + value.getLength());
        }
    }
    if (auto* issuer = CCertStore::GetCertificate(*this)) {
        UUCByteArray value; issuer->toByteArray(value);
        candidates.emplace_back(value.getContent(), value.getContent() + value.getLength());
    }
    cie::HttpOptions network;
    if (g_szVerifyProxy && *g_szVerifyProxy) {
        network.proxy = g_szVerifyProxy;
        network.proxyPort = g_nVerifyProxyPort;
        if (g_szVerifyProxyUsrPass) network.proxyCredentials = g_szVerifyProxyUsrPass;
    }
    // The claimed document signing time cannot authenticate a historical
    // revocation state. Validate current, signed issuer responses instead.
    return cie::checkRevocation(target, candidates, network, information);
}

cie::CertificateValidation CCertificate::validateTrust(CASN1SetOf* certificates, bool revocation)
{
    UUCByteArray encoded; toByteArray(encoded);
    cie::CertificateBytes target(encoded.getContent(), encoded.getContent() + encoded.getLength());
    std::vector<cie::CertificateBytes> candidates;
    for (int i = 0; certificates && i < certificates->size() && i < 64; ++i) {
        UUCByteArray bytes; certificates->elementAt(i).toByteArray(bytes);
        candidates.emplace_back(bytes.getContent(), bytes.getContent() + bytes.getLength());
    }
    cie::HttpOptions network;
    if (*g_szVerifyProxy) {
        network.proxy = g_szVerifyProxy; network.proxyPort = g_nVerifyProxyPort;
        if (g_szVerifyProxyUsrPass) network.proxyCredentials = g_szVerifyProxyUsrPass;
    }
    cie::TrustOptions options; options.checkRevocation = revocation;
    return cie::validateCertificate(target, candidates, network, options);
}

int CCertificate::verify()
{
    auto result = validateTrust(nullptr, false);
    if (result.trust.status != CIE_TRUST_TRUSTED) return 0;
    return VERIFIED_CERT_CHAIN | (result.trust.chainLength > 1 ?
        VERIFIED_CACERT_FOUND | VERIFIED_CACERT_SIGNATURE | VERIFIED_CACERT_VALIDITY : 0);
}


bool CCertificate::verifySignature(CCertificate& cert)
{
	//NSLog(@"Verify CERT signature");

    // OpenSSL
    UUCByteArray baCert;
    cert.toByteArray(baCert);

    std::unique_ptr<X509, decltype(&X509_free)> x509(nullptr, X509_free);

    const BYTE* content = baCert.getContent();
    x509.reset(d2i_X509(NULL, &content, baCert.getLength()));

    if (!x509) return false;
    std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> evp_pubkey(X509_get_pubkey(x509.get()), EVP_PKEY_free);
    if (!evp_pubkey) return false;

	CASN1BitString encryptedDigest(elementAt(2));
	UUCByteArray encDigest(*(UUCByteArray*)encryptedDigest.getValue());
	encDigest.remove(0);

    std::vector<BYTE> decrypted;
    int len = -1;

    const BYTE* encrypted = encDigest.getContent();
    const int encrypted_len = (int)encDigest.getLength();

    if (encrypted_len >= 0 && cie::recoverRsaPkcs1(evp_pubkey.get(), encrypted,
                static_cast<std::size_t>(encrypted_len), decrypted))
            len = static_cast<int>(decrypted.size());


    if(len > 0)
    {
        //NSLog(@"RSA OK");
        try
        {

			char szAux[100];

			UUCBufferedReader reader(decrypted.data(), len);
			CDigestInfo digestInfo(reader);
			//UUCByteArray* pauxdi = (UUCByteArray*)digestInfo.getValue();
			//szHex = pauxdi->toHexString();

			CASN1OctetString digest = digestInfo.getDigest();
			UUCByteArray* pDigestValue = (UUCByteArray*)digest.getValue();
			//szHex = pDigestValue->toHexString();

			// content
			UUCByteArray content;
			getCertificateInfo().toByteArray(content);


			BYTE* buff;
			int bufflen = 0;

			buff = (BYTE*)content.getContent();
			bufflen = content.getLength();

			CAlgorithmIdentifier digestAlgo(digestInfo.getDigestAlgorithm());
			CAlgorithmIdentifier sha256Algo(szSHA256OID);
			CAlgorithmIdentifier sha1Algo(szSHA1OID);
			if(digestAlgo.elementAt(0) == sha256Algo.elementAt(0))
			{
				//bitmask |= VERIFIED_SHA256;

				//NSLog(@"SHA256");


				BYTE hash[32];
				BYTE hash2[32];
	/*
				sha256_context	ctx256;
				sha256_starts(&ctx256);
				sha256_update(&ctx256, buff, bufflen);
				sha256_finish(&ctx256, hash);

				sha256_context	ctx2561;
				sha256_starts(&ctx2561);
				sha256_update(&ctx2561, content.getContent(), content.getLength());
				sha256_finish(&ctx2561, hash2);
*/
				cie::digestSHA2(buff, bufflen, hash, 0);
				cie::digestSHA2(content.getContent(), content.getLength(), hash2, 0);
/*
				SHA256_CTX	ctx256;
				SHA256_Init(&ctx256);
				SHA256_Update(&ctx256, buff, bufflen);
				SHA256_Final(hash, &ctx256);

				SHA256_CTX	ctx2561;
				SHA256_Init(&ctx2561);
				SHA256_Update(&ctx2561, content.getContent(), content.getLength());
				SHA256_Final(hash2, &ctx2561);
*/
				if(memcmp(hash, pDigestValue->getContent(), 32) == 0)
				{
					// verifica l'hash del content
					if(memcmp(hash2, hash, 32) == 0)
					{
						//NSLog(@"Verify OK");

						return true;
					}
				}
				else
				{
					//NSLog(@"Digest not match");
				}

			}
			else if(digestAlgo.elementAt(0) == sha1Algo.elementAt(0)) //if(digestAlgo == CAlgorithmIdentifier(szSHA1OID))
			{
				//NSLog(@"SHA1");

				// calcola l'hash SHA1
				cie::Sha1Digest sha;

				sha.reset();

				sha.update( buff, bufflen);

				sha.finish();

				sprintf(szAux, "%08X%08X%08X%08X%08X ", sha.words[0], sha.words[1], sha.words[2], sha.words[3], sha.words[4]);

				UUCByteArray hashaux(szAux);

				sha.reset();
				sha.update( content.getContent(), content.getLength());
				sha.finish();
				sprintf(szAux, "%08X%08X%08X%08X%08X ", sha.words[0], sha.words[1], sha.words[2], sha.words[3], sha.words[4]);
				UUCByteArray contentHash(szAux);


				if(memcmp(hashaux.getContent(), pDigestValue->getContent(), hashaux.getLength()) == 0)
				{
					// verifica l'hash del content
					if(memcmp(contentHash.getContent(), hashaux.getContent(), contentHash.getLength()) == 0)
					{
						//NSLog(@"Verify OK");

						return true;
					}
				}
				else
				{
					//NSLog(@"Digest not match");
				}
			}
			else
			{
//				NSLog(@"Warning HASH Algo not found");
			}

        }
        catch(CASN1Exception* ex)
        {
            delete ex;
            //NSLog(@"certificate:verify - ASN1Exception");
            return false;
        }
        catch(...)
        {
            //NSLog(@"certificate:verify - Generic exception");
            return false;
        }
    }

	return false;
}


/*
CASN1BitString& CCertificate::getSubjectPublicKeyInfo()
{
	return *(CASN1BitString*)getElementAt(2);
}
*/
/*
CASN1BitString& CCertificate::getSignature()
{
	return *(CASN1BitString*)getElementAt(2);
}
 */


long HTTPRequest(UUCByteArray& data, const char* url, const char* contentType, UUCByteArray& response)
{
    cie::HttpOptions options;
    if (g_szVerifyProxy && *g_szVerifyProxy) {
        options.proxy = g_szVerifyProxy; options.proxyPort = g_nVerifyProxyPort;
        if (g_szVerifyProxyUsrPass) options.proxyCredentials = g_szVerifyProxyUsrPass;
    }
    std::vector<unsigned char> request;
    if (data.getLength()) request.assign(data.getContent(), data.getContent() + data.getLength());
    auto result = cie::httpRequest(url ? url : "", request, contentType, options);
    if (result.error != CURLE_OK) return result.error;
    if (!result.body.empty()) response.append(result.body.data(), result.body.size());
    return result.body.empty() ? -1 : 0;
}

static size_t WriteCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
	UUCByteArray* pResponse = (UUCByteArray*)userp;
	size_t realsize = size * nmemb;
	//LOG_ERR((0, "WriteCallback", "response len: %d", realsize));
	pResponse->append((BYTE*)contents, realsize);

	return realsize;
}
