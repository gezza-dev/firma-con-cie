// SPDX-License-Identifier: BSD-3-Clause
#pragma once

extern "C" unsigned short cie_error;
static EVP_PKEY* callbackKey = nullptr;
static unsigned short callbackStatus = 0x9000;
static int callbackCalls = 0;
static short softwareCardCallback(unsigned char* input, size_t length,
                                  unsigned char* signature, size_t* signatureLength)
{
    ++callbackCalls;
    if (callbackStatus != 0x9000) return static_cast<short>(callbackStatus);
    try {
        auto result = rawRsaSign(callbackKey, input, length);
        if (*signatureLength < result.size()) return static_cast<short>(0x6F00);
        std::copy(result.begin(), result.end(), signature);
        *signatureLength = result.size();
        return static_cast<short>(0x9000);
    } catch (...) { return static_cast<short>(0x6F00); }
}
static void testEngineCallback(EVP_PKEY* key, X509* certificate)
{
    callbackKey = key; callbackCalls = 0; callbackStatus = 0x9000;
    engine_load_cie(softwareCardCallback);
    std::unique_ptr<ENGINE, decltype(&ENGINE_free)> engine(ENGINE_by_id("cie"), ENGINE_free);
    require(engine && ENGINE_init(engine.get()) == 1, "Compatibility ENGINE init");
    cie_x509_certificate = X509_dup(certificate);
    std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> publicKey(
        ENGINE_load_private_key(engine.get(), "cie", nullptr, nullptr), EVP_PKEY_free);
    require(publicKey != nullptr, "Compatibility ENGINE key load");
    for (const EVP_MD* md : {EVP_sha1(), EVP_sha256(), EVP_sha384(), EVP_sha512()}) {
        unsigned char hash[EVP_MAX_MD_SIZE]; unsigned int size=0;
        require(EVP_Digest("callback",8,hash,&size,md,nullptr)==1,"Callback digest");
        std::unique_ptr<EVP_PKEY_CTX,decltype(&EVP_PKEY_CTX_free)> ctx(
            EVP_PKEY_CTX_new(publicKey.get(),engine.get()),EVP_PKEY_CTX_free);
        require(ctx && EVP_PKEY_sign_init(ctx.get())==1 &&
                EVP_PKEY_CTX_set_rsa_padding(ctx.get(),RSA_PKCS1_PADDING)==1 &&
                EVP_PKEY_CTX_set_signature_md(ctx.get(),md)==1,"ENGINE signature context");
        size_t length=0; int calls=callbackCalls;
        require(EVP_PKEY_sign(ctx.get(),nullptr,&length,hash,size)==1 && callbackCalls==calls,
                "Size query must not access card");
        std::vector<unsigned char> signature(length);
        require(EVP_PKEY_sign(ctx.get(),signature.data(),&length,hash,size)==1 && callbackCalls==calls+1,
                "OpenSSL 3 must invoke the card callback");
        std::unique_ptr<EVP_PKEY_CTX,decltype(&EVP_PKEY_CTX_free)> verify(
            EVP_PKEY_CTX_new_from_pkey(nullptr,key,nullptr),EVP_PKEY_CTX_free);
        require(verify && EVP_PKEY_verify_init(verify.get())==1 &&
                EVP_PKEY_CTX_set_rsa_padding(verify.get(),RSA_PKCS1_PADDING)==1 &&
                EVP_PKEY_CTX_set_signature_md(verify.get(),md)==1 &&
                EVP_PKEY_verify(verify.get(),signature.data(),length,hash,size)==1,"Callback RSA signature verification");
        callbackStatus=0x6983; length=signature.size();
        require(EVP_PKEY_sign(ctx.get(),signature.data(),&length,hash,size)<=0 && cie_error==0x6983,
                "Card failure incorrectly reported as signature success");
        callbackStatus=0x9000; ERR_clear_error();
        require(EVP_PKEY_CTX_set_rsa_padding(ctx.get(),RSA_PKCS1_PSS_PADDING)==1,"PSS context setup");
        calls=callbackCalls; length=signature.size();
        require(EVP_PKEY_sign(ctx.get(),signature.data(),&length,hash,size)<=0 && callbackCalls==calls,
                "Unsupported PSS must not access card"); ERR_clear_error();
    }
    X509_free(cie_x509_certificate); cie_x509_certificate=nullptr;
    ENGINE_finish(engine.get()); callbackKey=nullptr;
}
static void testEncryptedPdfs()
{
    using namespace PoDoFo;
    std::vector<PdfEncryptionAlgorithm> algorithms={PdfEncryptionAlgorithm::RC4V1,
        PdfEncryptionAlgorithm::RC4V2, PdfEncryptionAlgorithm::AESV2, PdfEncryptionAlgorithm::AESV3R6};
    for (auto algorithm : algorithms) {
        PdfMemDocument document;
        document.GetPages().CreatePage(Rect(0,0,595,842));
        document.GetMetadata().SetTitle(PdfString("Native encrypted PDF"));
        document.SetEncrypted("", "owner", PdfPermissions::Print, algorithm,
            algorithm == PdfEncryptionAlgorithm::RC4V1 ? PdfKeyLength::L40 :
            algorithm == PdfEncryptionAlgorithm::AESV3R6 ? PdfKeyLength::L256 : PdfKeyLength::L128);
        charbuff buffer; BufferStreamDevice output(buffer);
        document.Save(output);
        PdfMemDocument probe;
        probe.LoadFromBuffer(bufferview(buffer.data(), buffer.size()));
        require(probe.GetInfo() && probe.GetInfo()->GetTitle().has_value() &&
                probe.GetInfo()->GetTitle()->GetString() == "Native encrypted PDF",
                "Encrypted PDF metadata did not decrypt");
        PDFVerifier loaded;
        require(loaded.Load(buffer.data(), int(buffer.size()))==0,
                "SDK cannot load existing encrypted PDF");
    }
    std::unique_ptr<EVP_CIPHER,decltype(&EVP_CIPHER_free)> legacy(
        EVP_CIPHER_fetch(nullptr,"RC4",nullptr),EVP_CIPHER_free);
    require(legacy && OSSL_PROVIDER_available(nullptr,"legacy"),"Static legacy provider unavailable");
}

// In-memory TLS proves that the compatibility engine does not replace software
// private-key operations used by HTTPS/TSA/CRL clients after engine registration.
static void testTls(EVP_PKEY* key, X509* certificate)
{
    for (int version : {TLS1_2_VERSION,TLS1_3_VERSION}) {
        std::unique_ptr<SSL_CTX,decltype(&SSL_CTX_free)> clientContext(SSL_CTX_new(TLS_client_method()),SSL_CTX_free);
        std::unique_ptr<SSL_CTX,decltype(&SSL_CTX_free)> serverContext(SSL_CTX_new(TLS_server_method()),SSL_CTX_free);
        require(clientContext && serverContext,"TLS context allocation");
        require(SSL_CTX_set_min_proto_version(clientContext.get(),version)==1 &&
                SSL_CTX_set_max_proto_version(clientContext.get(),version)==1 &&
                SSL_CTX_set_min_proto_version(serverContext.get(),version)==1 &&
                SSL_CTX_set_max_proto_version(serverContext.get(),version)==1,"TLS version configuration");
        SSL_CTX_set_verify(clientContext.get(),SSL_VERIFY_PEER,nullptr);
        require(X509_STORE_add_cert(SSL_CTX_get_cert_store(clientContext.get()),certificate)==1 &&
                SSL_CTX_use_certificate(serverContext.get(),certificate)==1 &&
                SSL_CTX_use_PrivateKey(serverContext.get(),key)==1,"TLS trust/key setup");
        std::unique_ptr<SSL,decltype(&SSL_free)> client(SSL_new(clientContext.get()),SSL_free),
                                                server(SSL_new(serverContext.get()),SSL_free);
        BIO *clientBio=nullptr,*serverBio=nullptr;
        require(client && server && BIO_new_bio_pair(&clientBio,0,&serverBio,0)==1,"TLS memory channel");
        SSL_set_bio(client.get(),clientBio,clientBio); SSL_set_bio(server.get(),serverBio,serverBio);
        SSL_set_connect_state(client.get()); SSL_set_accept_state(server.get());
        for (int step=0;step<100 && (!SSL_is_init_finished(client.get()) || !SSL_is_init_finished(server.get()));++step) {
            for (SSL* connection : {client.get(),server.get()}) {
                if (SSL_is_init_finished(connection)) continue;
                int result=SSL_do_handshake(connection);
                if (result!=1) {
                    int error=SSL_get_error(connection,result);
                    if (error!=SSL_ERROR_WANT_READ && error!=SSL_ERROR_WANT_WRITE) ERR_print_errors_fp(stderr);
                    require(error==SSL_ERROR_WANT_READ || error==SSL_ERROR_WANT_WRITE,"TLS handshake failure");
                }
            }
        }
        require(SSL_is_init_finished(client.get()) && SSL_is_init_finished(server.get()) &&
                SSL_get_verify_result(client.get())==X509_V_OK && SSL_version(client.get())==version,
                "TLS handshake/peer verification incomplete");
        const char payload[]="native TLS"; char actual[sizeof(payload)]={};
        require(SSL_write(client.get(),payload,sizeof(payload))==sizeof(payload) &&
                SSL_read(server.get(),actual,sizeof(actual))==sizeof(payload) &&
                std::equal(actual,actual+sizeof(actual),payload),"TLS application data failed");
    }
}
