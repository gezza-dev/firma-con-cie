#include "CIEEngine.h"
#include "PdfSignatureGenerator.h"
#include "PdfVerifier.h"
#include "disigonsdk.h"
#include <openssl/cms.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#include <fstream>
#include <filesystem>
#include <sys/stat.h>
#include "Native/Digest.h"
#include <cryptopp/sha.h>
#include <png.h>
#include <unistd.h>
#include <algorithm>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>

extern "C" X509* cie_x509_certificate;

static void require(bool condition, const char* message)
{
    if (!condition) throw std::runtime_error(message);
}

static EVP_PKEY* makeKey(int bits = 2048)
{
    EVP_PKEY_CTX* context = EVP_PKEY_CTX_new_from_name(nullptr, "RSA", nullptr);
    EVP_PKEY* key = NULL;
    require(context && EVP_PKEY_keygen_init(context) == 1 &&
            EVP_PKEY_CTX_set_rsa_keygen_bits(context, bits) == 1 &&
            EVP_PKEY_keygen(context, &key) == 1, "RSA key generation failed");
    EVP_PKEY_CTX_free(context);
    return key;
}

static X509* makeCertificate(EVP_PKEY* key)
{
    X509* certificate = X509_new();
    require(certificate != NULL, "Certificate allocation failed");
    X509_set_version(certificate, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(certificate), 1);
    X509_gmtime_adj(X509_get_notBefore(certificate), 0);
    X509_gmtime_adj(X509_get_notAfter(certificate), 3600);
    X509_set_pubkey(certificate, key);
    X509_NAME_add_entry_by_txt(X509_get_subject_name(certificate), "CN", MBSTRING_ASC,
        reinterpret_cast<const unsigned char*>("SDK integration test"), -1, -1, 0);
    X509_set_issuer_name(certificate, X509_get_subject_name(certificate));
    X509V3_CTX extensions;
    X509V3_set_ctx(&extensions, certificate, certificate, NULL, NULL, 0);
    X509_EXTENSION* identifier = X509V3_EXT_conf_nid(NULL, &extensions, NID_subject_key_identifier, (char*)"hash");
    require(identifier && X509_add_ext(certificate, identifier, -1) == 1, "Certificate extension failed");
    X509_EXTENSION_free(identifier);
    require(X509_sign(certificate, key, EVP_sha256()) > 0, "Certificate signing failed");
    return certificate;
}

class TestPng
{
public:
    char path[1024] = "/tmp/cie-sdk-test-XXXXXX.png";
    TestPng()
    {
#ifdef _WIN32
        char temporary[1024] = {};
        require(GetTempFileNameA(".", "cie", 0, temporary) != 0, "Could not create PNG fixture");
        // PoDoFo selects the image decoder from the filename extension.
        // Keep the uniquely reserved file, but give the PNG its actual suffix.
        const std::string pngPath = std::string(temporary) + ".png";
        if (pngPath.size() >= sizeof(path) || !MoveFileExA(temporary, pngPath.c_str(), 0)) {
            DeleteFileA(temporary);
            require(false, "Could not rename PNG fixture");
        }
        std::copy(pngPath.c_str(), pngPath.c_str() + pngPath.size() + 1, path);
#else
        int descriptor = mkstemps(path, 4);
        require(descriptor >= 0, "Could not create PNG fixture");
        close(descriptor);
#endif
        png_image image = {};
        image.version = PNG_IMAGE_VERSION;
        image.width = image.height = 2;
        image.format = PNG_FORMAT_RGBA;
        unsigned char pixels[] = {255, 0, 0, 255, 0, 255, 0, 128,
                                  0, 0, 255, 0, 255, 255, 255, 255};
        require(png_image_write_to_file(&image, path, 0, pixels, 0, NULL) == 1,
                "Could not write transparent PNG fixture");
    }
    ~TestPng() { unlink(path); }
};

static void testCryptoPP()
{
    const unsigned char expected[] = {
        0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,
        0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad};
    unsigned char actual[CryptoPP::SHA256::DIGESTSIZE];
    CryptoPP::SHA256().CalculateDigest(actual, reinterpret_cast<const unsigned char*>("abc"), 3);
    require(std::equal(actual, actual + sizeof(actual), expected), "Crypto++ SHA-256 vector failed");
}

static void testEngine(EVP_PKEY* key, X509* certificate)
{
    engine_load_cie(NULL);
    ENGINE* engine = ENGINE_by_id("cie");
    require(engine && ENGINE_init(engine) == 1, "Engine initialization failed");
    require(ENGINE_load_public_key(engine, "cie", NULL, NULL) == NULL,
            "A missing certificate must not produce a public key");
    ERR_clear_error();
    cie_x509_certificate = X509_dup(certificate);
    EVP_PKEY* publicKey = ENGINE_load_public_key(engine, "cie", NULL, NULL);
    require(publicKey && EVP_PKEY_cmp(key, publicKey) == 1, "Engine returned the wrong public key");
    EVP_PKEY_free(publicKey);
    X509_free(cie_x509_certificate);
    cie_x509_certificate = NULL;
    ENGINE_finish(engine);
    ENGINE_free(engine);
}

static std::vector<char> signPdf(const std::vector<char>& input, EVP_PKEY* key,
                               X509* certificate, const char* field, int expectedSignatures,
                               const char* imagePath = NULL, bool legacySha1 = false)
{
    PdfSignatureGenerator generator;
    require(generator.Load(input.data(), input.size()) == expectedSignatures, "PDF loading/signature count failed");
    generator.InitSignature(0, 0.1f, 0.1f, 0.4f, 0.1f,
        "ARM migration test", "Reason", "Test signer", "Name", "Rome", "Location",
        field, legacySha1 ? "adbe.pkcs7.sha1" : "adbe.pkcs7.detached", imagePath, "SDK test signature", NULL, NULL);
    UUCByteArray toSign;
    generator.GetBufferForSignature(toSign);
    unsigned char hash[20];
    if (legacySha1) cie::digest(EVP_sha1(), toSign.getContent(), toSign.getLength(), hash);
    BIO* data = legacySha1 ? BIO_new_mem_buf(hash, sizeof(hash)) : BIO_new_mem_buf(toSign.getContent(), toSign.getLength());
    CMS_ContentInfo* cms = CMS_sign(certificate, key, NULL, data, CMS_BINARY | (legacySha1 ? 0 : CMS_DETACHED));
    require(cms != NULL, "CMS signing failed");
    int length = i2d_CMS_ContentInfo(cms, NULL);
    std::vector<unsigned char> signature(length);
    unsigned char* cursor = signature.data();
    require(i2d_CMS_ContentInfo(cms, &cursor) == length, "CMS encoding failed");
    generator.SetSignature(reinterpret_cast<const char*>(signature.data()), signature.size());
    UUCByteArray result;
    generator.GetSignedPdf(result);
    CMS_ContentInfo_free(cms);
    BIO_free(data);
    return std::vector<char>(result.getContent(), result.getContent() + result.getLength());
}

static void verifyPdf(const std::vector<char>& pdf, int expectedSignatures)
{
    PDFVerifier verifier;
    require(verifier.Load(pdf.data(), pdf.size()) == 0, "SDK PDF verifier cannot load signed PDF");
    for (int i = 0; i < expectedSignatures; ++i) {
        char signatureType[256] = {};
        int result = verifier.VerifySignature(i, nullptr, signatureType, nullptr);
        require(result >= 0 && (result & VERIFIED_SIGNATURE),
                "SDK verifier rejects a valid externally generated PDF signature");
        require(result & VERIFIED_CERT_VALIDITY, "SDK verifier rejects a current certificate");
    }
    PoDoFo::PdfMemDocument document;
    document.LoadFromBuffer(PoDoFo::bufferview(pdf.data(), pdf.size()));
    require(PDFVerifier::GetNumberOfSignatures(&document) == expectedSignatures,
            "Signed PDF has the wrong number of signatures");
    int verified = 0;
    for (auto it = document.GetObjects().begin(); it != document.GetObjects().end(); ++it) {
        const PoDoFo::PdfObject* object = *it;
        if (!object->IsDictionary()) continue;
        const PoDoFo::PdfObject* range = object->GetDictionary().GetKey("ByteRange");
        const PoDoFo::PdfObject* contents = object->GetDictionary().GetKey("Contents");
        if (!range || !contents || !contents->IsString()) continue;
        const PoDoFo::PdfArray& offsets = range->GetArray();
        require(offsets.size() == 4, "Invalid PDF ByteRange");
        std::vector<char> signedBytes;
        for (size_t i = 0; i < 4; i += 2) {
            auto start = offsets[i].GetNumber();
            auto length = offsets[i + 1].GetNumber();
            require(start >= 0 && length >= 0 && static_cast<size_t>(start + length) <= pdf.size(), "ByteRange exceeds PDF bounds");
            signedBytes.insert(signedBytes.end(), pdf.begin() + start, pdf.begin() + start + length);
        }
        const PoDoFo::PdfString& value = contents->GetString();
        const unsigned char* cursor = reinterpret_cast<const unsigned char*>(value.GetRawData().data());
        CMS_ContentInfo* cms = d2i_CMS_ContentInfo(NULL, &cursor, value.GetRawData().size());
        BIO* input = BIO_new_mem_buf(signedBytes.data(), signedBytes.size());
        require(cms && CMS_verify(cms, NULL, NULL, input, NULL, CMS_BINARY | CMS_NO_SIGNER_CERT_VERIFY) == 1,
                "PDF CMS signature does not verify");
        BIO_free(input);
        CMS_ContentInfo_free(cms);
        ++verified;
    }
    require(verified == expectedSignatures, "Missing cryptographically verified PDF signatures");
}

#include "native_replacement_tests.h"
#include "openssl3_tests.h"

int main(int argc, char** argv)
{
    try {
        // A local timezone ahead of UTC must not expire a certificate with an hour left.
#ifdef _WIN32
        _putenv_s("TZ", "UTC-2");
#else
        setenv("TZ", "UTC-2", 1);
#endif
        tzset();
        require(cie::initializeOpenSsl(), "Static OpenSSL default/legacy providers failed");
        require(OpenSSL_version_num() == OPENSSL_VERSION_NUMBER,
                "Wrong runtime OpenSSL version");
        // Pull the full public SDK implementation into the native link as well.
        DISIGON_CTX context = disigon_verify_init();
        require(context != NULL, "SDK context initialization failed");
        std::string excessivePath(MAX_PATH + 10, 'x');
        require(disigon_verify_set(context, DISIGON_OPT_INPUTFILE, excessivePath.data()) != 0,
                "Oversized SDK path accepted");
        disigon_verify_cleanup(context);
        std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> key(makeKey(), EVP_PKEY_free);
        std::unique_ptr<X509, decltype(&X509_free)> certificate(makeCertificate(key.get()), X509_free);
        testEngine(key.get(), certificate.get());
        testCryptoPP();
        testNativeDigests();
        testRsaRecovery(key.get());
        for (int bits : {1024, 4096}) {
            std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> other(makeKey(bits), EVP_PKEY_free);
            testRsaRecovery(other.get());
        }
        testNativeUtilities();
        testSdkCms(key.get(), certificate.get());
        testEngineCallback(key.get(), certificate.get());
        testEncryptedPdfs();
        testTls(key.get(), certificate.get());
        PoDoFo::PdfMemDocument document;
        document.GetPages().CreatePage(PoDoFo::Rect(0, 0, 595, 842));
        PoDoFo::charbuff buffer;
        PoDoFo::BufferStreamDevice output(buffer);
        document.Save(output);
        std::vector<char> input(buffer.begin(), buffer.end());
        TestPng png;
        auto first = signPdf(input, key.get(), certificate.get(), "FirstSignature", 0, png.path);
        require(std::string(first.begin(), first.end()).find("/SMask") != std::string::npos,
                "Signature appearance lost PNG transparency");
        verifyPdf(first, 1);
        auto second = signPdf(first, key.get(), certificate.get(), "SecondSignature", 1);
        require(second.size() > first.size() && std::equal(first.begin(), first.end(), second.begin()),
                "Incremental signing changed the previously signed PDF bytes");
        verifyPdf(second, 2);
        auto legacy = signPdf(input, key.get(), certificate.get(), "LegacySha1Signature", 0, nullptr, true);
        PDFVerifier legacyVerifier;
        require(legacyVerifier.Load(legacy.data(), legacy.size()) == 0, "Legacy SHA-1 PDF load");
        char legacyType[256] = {};
        int legacyResult = legacyVerifier.VerifySignature(0, nullptr, legacyType, nullptr);
        require(legacyResult >= 0 && (legacyResult & VERIFIED_SIGNATURE), "Valid legacy SHA-1 PDF rejected");
        legacy[7] = legacy[7] == '7' ? '6' : '7';
        require(legacyVerifier.Load(legacy.data(), legacy.size()) == 0, "Altered legacy SHA-1 PDF load");
        legacyResult = legacyVerifier.VerifySignature(0, nullptr, legacyType, nullptr);
        require(legacyResult < 0 || !(legacyResult & VERIFIED_SIGNATURE), "Altered legacy SHA-1 PDF accepted");
        if (argc == 2) {
            std::string directory = argv[1];
            std::filesystem::create_directories(std::filesystem::u8path(directory));
            auto save = [&](const char* name, const std::vector<char>& bytes) {
                std::ofstream out(std::filesystem::u8path(directory + "/" + name), std::ios::binary);
                out.write(bytes.data(), bytes.size());
                require(out.good(), "Could not write verification fixture");
            };
            save("unsigned.pdf", input);
            save("valid.pdf", first);
            save("two-signatures.pdf", second);
            auto changed = first;
            require(changed.size() > 8 && std::string(changed.data(), 7) == "%PDF-1.",
                    "Unexpected PDF test header");
            changed[7] = changed[7] == '7' ? '6' : '7'; // Valid syntax, changed signed bytes.
            save("tampered.pdf", changed);
            const char content[] = "CIE verification regression fixture";
            BIO* data = BIO_new_mem_buf(content, sizeof(content)-1);
            CMS_ContentInfo* cms = CMS_sign(certificate.get(), key.get(), NULL, data, CMS_BINARY);
            require(cms != nullptr, "Could not generate attached CMS fixture");
            int size = i2d_CMS_ContentInfo(cms, nullptr);
            std::vector<char> encoded(size);
            unsigned char* cursor = reinterpret_cast<unsigned char*>(encoded.data());
            require(i2d_CMS_ContentInfo(cms, &cursor) == size, "CMS fixture encoding failed");
            save("valid.p7m", encoded);
            CMS_ContentInfo_free(cms);
            BIO_free(data);
            auto where = std::search(encoded.begin(), encoded.end(), content, content + sizeof(content)-1);
            require(where != encoded.end(), "CMS fixture content missing");
            *where = 'X';
            save("tampered.p7m", encoded);
        }
        std::cout << "OpenSSL 3.5 providers, RSA/engine callbacks, TLS 1.2/1.3, encrypted PDFs, CMS SHA-1/256 and incremental PDF signatures passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    } catch (const PoDoFo::PdfError& error) {
        error.PrintErrorMsg();
        return 1;
    }
    return 0;
}
