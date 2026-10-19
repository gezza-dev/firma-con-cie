cmake_minimum_required(VERSION 3.23)

project(cie_sign_sdk LANGUAGES C CXX)

set(CIE_DEPENDENCY_PREFIX "" CACHE PATH "Prefix produced by scripts/build-dependencies.py")
if(NOT CIE_DEPENDENCY_PREFIX)
    message(FATAL_ERROR "Set CIE_DEPENDENCY_PREFIX to the native dependency prefix; see README.md")
endif()

set(CMAKE_CXX_STANDARD 17)

set(DEPENDENCIES_DIR "${CIE_DEPENDENCY_PREFIX}")
set(SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)


set(SRC_LIST
    ${SOURCE_DIR}/Native/CadesCosign.cpp
    ${SOURCE_DIR}/Native/TemporalValidation.cpp
    ${SOURCE_DIR}/Native/CertificateTrust.cpp
    ${SOURCE_DIR}/Native/SystemTrust.cpp
    ${SOURCE_DIR}/Native/RsaRecovery.cpp
    ${SOURCE_DIR}/Native/HttpClient.cpp
    ${SOURCE_DIR}/Native/Revocation.cpp
    ${SOURCE_DIR}/Base64.cpp
    ${SOURCE_DIR}/BigInteger.cpp
    ${SOURCE_DIR}/BigIntegerAlgorithms.cpp
    ${SOURCE_DIR}/BigIntegerUtils.cpp
    ${SOURCE_DIR}/BigUnsigned.cpp
    ${SOURCE_DIR}/BigUnsignedInABase.cpp
    ${SOURCE_DIR}/CIESigner.cpp
    ${SOURCE_DIR}/CiePdfSignatureField.cpp
    ${SOURCE_DIR}/CIEEngine.c
    ${SOURCE_DIR}/CIEEngineHelper.c
    ${SOURCE_DIR}/CertStore.cpp
    ${SOURCE_DIR}/CounterSignatureGenerator.cpp
    ${SOURCE_DIR}/SignatureGenerator.cpp
    ${SOURCE_DIR}/LdapCrl.cpp
    ${SOURCE_DIR}/M7MParser.cpp
    ${SOURCE_DIR}/PdfSignatureGenerator.cpp
    ${SOURCE_DIR}/PdfVerifier.cpp
    ${SOURCE_DIR}/SignedDataGeneratorEx.cpp
    ${SOURCE_DIR}/SignedDocument.cpp
    ${SOURCE_DIR}/SignerInfoGenerator.cpp
    ${SOURCE_DIR}/TSAClient.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../platform/SdkLog.cpp
    ${SOURCE_DIR}/UUCStringTable.cpp
    ${SOURCE_DIR}/UUCTextFileReader.cpp
    ${SOURCE_DIR}/UUCTextFileWriter.cpp
    ${SOURCE_DIR}/XAdESGenerator.cpp
    ${SOURCE_DIR}/XAdESVerifier.cpp
    ${SOURCE_DIR}/definitions.cpp
    ${SOURCE_DIR}/disigonsdk.cpp
    ${SOURCE_DIR}/ASN1/ASN1BitString.cpp
    ${SOURCE_DIR}/ASN1/ASN1Boolean.cpp
    ${SOURCE_DIR}/ASN1/ASN1GenericSequence.cpp
    ${SOURCE_DIR}/ASN1/ASN1Integer.cpp
    ${SOURCE_DIR}/ASN1/ASN1Null.cpp
    ${SOURCE_DIR}/ASN1/ASN1Object.cpp
    ${SOURCE_DIR}/ASN1/ASN1ObjectIdentifier.cpp
    ${SOURCE_DIR}/ASN1/ASN1Octetstring.cpp
    ${SOURCE_DIR}/ASN1/ASN1OptionalField.cpp
    ${SOURCE_DIR}/ASN1/ASN1Sequence.cpp
    ${SOURCE_DIR}/ASN1/ASN1Setof.cpp
    ${SOURCE_DIR}/ASN1/ASN1UTCTime.cpp
    ${SOURCE_DIR}/ASN1/AlgorithmIdentifier.cpp
    ${SOURCE_DIR}/ASN1/Certificate.cpp
    ${SOURCE_DIR}/ASN1/CertificateInfo.cpp
    ${SOURCE_DIR}/ASN1/ContentInfo.cpp
    ${SOURCE_DIR}/ASN1/ContentType.cpp
    ${SOURCE_DIR}/ASN1/Crl.cpp
    ${SOURCE_DIR}/ASN1/DigestInfo.cpp
    ${SOURCE_DIR}/ASN1/IssuerAndSerialNumber.cpp
    ${SOURCE_DIR}/ASN1/Name.cpp
    ${SOURCE_DIR}/ASN1/OCSPRequest.cpp
    ${SOURCE_DIR}/ASN1/PKIStatusInfo.cpp
    ${SOURCE_DIR}/ASN1/RSAPrivateKey.cpp
    ${SOURCE_DIR}/ASN1/RSAPublicKey.cpp
    ${SOURCE_DIR}/ASN1/RelativeDistinguishedName.cpp
    ${SOURCE_DIR}/ASN1/SignedData.cpp
    ${SOURCE_DIR}/ASN1/SignerInfo.cpp
    ${SOURCE_DIR}/ASN1/SubjectPublicKeyInfo.cpp
    ${SOURCE_DIR}/ASN1/TSTInfo.cpp
    ${SOURCE_DIR}/ASN1/TimeStampData.cpp
    ${SOURCE_DIR}/ASN1/TimeStampRequest.cpp
    ${SOURCE_DIR}/ASN1/TimeStampResponse.cpp
    ${SOURCE_DIR}/ASN1/TimeStampToken.cpp
    ${SOURCE_DIR}/ASN1/ByteReader.cpp
    ${SOURCE_DIR}/RSA/rc2.c
    ${SOURCE_DIR}/RSA/rc2.h
    ${SOURCE_DIR}/CSP/IAS.cpp
    ${SOURCE_DIR}/CSP/ATR.cpp
    ${SOURCE_DIR}/CSP/ExtAuthKey.cpp
    ${SOURCE_DIR}/PCSC/APDU.cpp
    ${SOURCE_DIR}/PCSC/CardLocker.cpp
    ${SOURCE_DIR}/PCSC/PCSC.cpp
    ${SOURCE_DIR}/PCSC/Token.cpp
    ${SOURCE_DIR}/Util/Array.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../platform/Cache.cpp
    ${SOURCE_DIR}/Util/CryptoppUtils.cpp
    ${SOURCE_DIR}/Util/funccallinfo.cpp
    ${SOURCE_DIR}/Util/IniSettings.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../platform/LegacyLog.cpp
    ${SOURCE_DIR}/Util/ModuleInfo.cpp
    ${SOURCE_DIR}/Util/TLV.cpp
    ${SOURCE_DIR}/Util/util.cpp
    ${SOURCE_DIR}/Util/UtilException.cpp
    ${SOURCE_DIR}/Util/UUCByteArray.cpp
    ${SOURCE_DIR}/Util/UUCProperties.cpp
    ${SOURCE_DIR}/Util/UUCTextFileReader.cpp
    ${SOURCE_DIR}/Util/SyncroMutex.cpp
    ${SOURCE_DIR}/Crypto/AES.cpp
    ${SOURCE_DIR}/Crypto/ASNParser.cpp
    ${SOURCE_DIR}/Crypto/Base64.cpp
    ${SOURCE_DIR}/Crypto/DES3.cpp
    ${SOURCE_DIR}/Crypto/MAC.cpp
    ${SOURCE_DIR}/Crypto/MD5.cpp
    ${SOURCE_DIR}/Crypto/RSA.cpp
    ${SOURCE_DIR}/Crypto/SHA1.cpp
    ${SOURCE_DIR}/Crypto/SHA256.cpp
    ${SOURCE_DIR}/Crypto/SHA512.cpp
    )

add_library(${PROJECT_NAME} STATIC ${SRC_LIST})
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/root.pem" CIE_ROOT_PEM)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/subca1.pem" CIE_SUBCA1_PEM)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/subca002.pem" CIE_SUBCA002_PEM)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/subca003.pem" CIE_SUBCA003_PEM)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/manifest.json" CIE_TRUST_MANIFEST)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/difesa/difesa-signing.pem" DIFESA_SIGNING_PEM)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/difesa/difesa-tsa.pem" DIFESA_TSA_PEM)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/trust/difesa/manifest.json" DIFESA_TRUST_MANIFEST)
foreach(certificate difesa-signing.pem difesa-tsa.pem)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/trust/difesa/${certificate}")
    file(SHA256 "${CMAKE_CURRENT_SOURCE_DIR}/trust/difesa/${certificate}" actual_digest)
    string(JSON expected_digest GET "${DIFESA_TRUST_MANIFEST}" pemSha256 "${certificate}")
    if(NOT actual_digest STREQUAL expected_digest)
        message(FATAL_ERROR "PKI Difesa authority checksum mismatch: ${certificate}")
    endif()
endforeach()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/trust/difesa/manifest.json")
foreach(certificate root.pem subca1.pem subca002.pem subca003.pem)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/trust/${certificate}")
    file(SHA256 "${CMAKE_CURRENT_SOURCE_DIR}/trust/${certificate}" actual_digest)
    string(JSON expected_digest GET "${CIE_TRUST_MANIFEST}" pemSha256 "${certificate}")
    if(NOT actual_digest STREQUAL expected_digest)
        message(FATAL_ERROR "CIE authority checksum mismatch: ${certificate}")
    endif()
endforeach()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/trust/manifest.json")
configure_file(${SOURCE_DIR}/Native/TrustMaterial.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/generated/TrustMaterial.h @ONLY)
target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/generated)

set(INCLUDE_LIST
    ${INCLUDE_DIR}
    ${SOURCE_DIR}/ASN1
    ${SOURCE_DIR}
    ${SOURCE_DIR}/RSA
    ${SOURCE_DIR}/PCSC
    ${SOURCE_DIR}/CSP
    ${SOURCE_DIR}/Util
    ${SOURCE_DIR}/Crypto
    ${DEPENDENCIES_DIR}/include/freetype2
    ${DEPENDENCIES_DIR}/include/libxml2
    ${DEPENDENCIES_DIR}/include/podofo
 )

target_include_directories(${PROJECT_NAME} PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../platform")
target_include_directories(${PROJECT_NAME} BEFORE PUBLIC "${DEPENDENCIES_DIR}/include")
target_include_directories(${PROJECT_NAME} PRIVATE ${INCLUDE_LIST})
target_include_directories(${PROJECT_NAME} PUBLIC
    $<BUILD_INTERFACE:${INCLUDE_DIR}>
    $<BUILD_INTERFACE:${DEPENDENCIES_DIR}/include>
    $<BUILD_INTERFACE:${DEPENDENCIES_DIR}/include/freetype2>
    $<BUILD_INTERFACE:${DEPENDENCIES_DIR}/include/libxml2>)
target_compile_definitions(${PROJECT_NAME} PUBLIC CIE_USE_UPSTREAM_PODOFO=1 CRYPTOPP_DISABLE_ASM=1 PODOFO_STATIC=1)

# Explicit archive paths keep Intel vendored binaries and Homebrew dylibs out.
set(CIE_STATIC_DEPENDENCIES podofo podofo_private podofo_3rdparty curl ssl crypto cryptopp fontconfig freetype
    png16 xml2 expat iconv charset bz2 z)
foreach(dependency IN LISTS CIE_STATIC_DEPENDENCIES)
    set(archive "${DEPENDENCIES_DIR}/lib/lib${dependency}.a")
    if(NOT EXISTS "${archive}")
        message(FATAL_ERROR "Missing ${archive}; run scripts/build-dependencies.py first")
    endif()
    target_link_libraries(${PROJECT_NAME} PUBLIC "${archive}")
endforeach()
if(APPLE)
    target_link_libraries(${PROJECT_NAME} PUBLIC "-framework PCSC" "-framework CoreFoundation" "-framework Security" "-framework SystemConfiguration" ldap lber)
elseif(WIN32)
    target_link_libraries(${PROJECT_NAME} PUBLIC winscard ws2_32 crypt32 bcrypt secur32 iphlpapi wldap32)
    target_compile_definitions(${PROJECT_NAME} PUBLIC CURL_STATICLIB LIBXML_STATIC NOMINMAX WIN32_LEAN_AND_MEAN)
else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(PCSC REQUIRED IMPORTED_TARGET libpcsclite)
    find_package(Threads REQUIRED)
    target_link_libraries(${PROJECT_NAME} PUBLIC PkgConfig::PCSC Threads::Threads ${CMAKE_DL_LIBS})
endif()

include(GNUInstallDirs)
install(TARGETS ${PROJECT_NAME} ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(FILES ${INCLUDE_DIR}/disigonsdk.h ${INCLUDE_DIR}/CertificateValidation.h ${INCLUDE_DIR}/TemporalValidation.h ${INCLUDE_DIR}/CIEEngine.h
    ${INCLUDE_DIR}/definitions.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cie_sign_sdk)

# Preserve licence texts with standalone SDK installations as well.
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSES"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/cie-sign-sdk")
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/trust/"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/cie-sign-sdk/cie-authorities")
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE_AUDIT.md"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/cie-sign-sdk")

option(CIE_BUILD_TESTS "Build SDK integration tests without a physical CIE" ON)
add_executable(cie_crl_fetch ${SOURCE_DIR}/Native/CrlFetch.cpp)
target_include_directories(cie_crl_fetch PRIVATE ${SOURCE_DIR}/Native)
target_link_libraries(cie_crl_fetch PRIVATE ${PROJECT_NAME})
if(CIE_BUILD_TESTS)
    enable_testing()
    add_executable(cie_trust_probe tests/trust_probe.cpp tests/middleware_stubs.cpp)
    target_include_directories(cie_trust_probe PRIVATE ${SOURCE_DIR} ${SOURCE_DIR}/Util ${SOURCE_DIR}/ASN1)
    target_link_libraries(cie_trust_probe PRIVATE ${PROJECT_NAME})
    add_executable(cie_security_tests tests/security_tests.cpp tests/middleware_stubs.cpp)
    target_include_directories(cie_security_tests PRIVATE ${SOURCE_DIR} ${SOURCE_DIR}/Util ${SOURCE_DIR}/ASN1)
    target_link_libraries(cie_security_tests PRIVATE ${PROJECT_NAME})
    add_test(NAME cie_security_tests COMMAND cie_security_tests)
    add_executable(cie_sdk_tests tests/sdk_tests.cpp tests/middleware_stubs.cpp)
    target_include_directories(cie_sdk_tests PRIVATE ${SOURCE_DIR} ${SOURCE_DIR}/Util ${SOURCE_DIR}/ASN1)
    target_link_libraries(cie_sdk_tests PRIVATE ${PROJECT_NAME})
    add_test(NAME cie_sdk_tests COMMAND cie_sdk_tests "${CMAKE_CURRENT_BINARY_DIR}/verification-fixtures")
    set_tests_properties(cie_sdk_tests PROPERTIES FIXTURES_SETUP CIEVerificationFixtures)
endif()
