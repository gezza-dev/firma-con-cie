// SPDX-License-Identifier: BSD-3-Clause
#include "ASN1/ASN1Object.h"
#include "ASN1/CertificateInfo.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <vector>

int main() {
    try {
        struct Case { unsigned size; std::vector<BYTE> header; };
        const Case cases[] = {
            {0, {0x04, 0}}, {127, {0x04, 127}}, {128, {0x04, 0x81, 0x80}},
            {255, {0x04, 0x81, 0xff}}, {256, {0x04, 0x82, 1, 0}},
            {257, {0x04, 0x82, 1, 1}}, {65535, {0x04, 0x82, 0xff, 0xff}},
            {65536, {0x04, 0x83, 1, 0, 0}},
        };
        for (const auto& item : cases) {
            std::vector<BYTE> content(item.size, 0xa5);
            UUCByteArray value(content.data(), content.size()), encoded;
            CASN1Object original(0x04, value);
            original.toByteArray(encoded);
            if (encoded.getLength() != item.header.size() + item.size ||
                !std::equal(item.header.begin(), item.header.end(), encoded.getContent()))
                throw std::runtime_error("Incorrect DER length octets");
            CASN1Object decoded(encoded);
            if (decoded.getTag() != 0x04 || decoded.getLength() != item.size ||
                !std::equal(content.begin(), content.end(), decoded.getValue()->getContent()))
                throw std::runtime_error("DER round-trip changed content");
        }
        // X.509 extensions are optional: the final public-key field is not
        // an extension wrapper, even when its bytes look like DER lengths.
        CASN1Sequence fields;
        CCertificateInfo empty(fields);
        if (empty.getExtensions().size() != 0)
            throw std::runtime_error("Empty certificate has extensions");
        const BYTE keyBytes[] = {0, 0xff, 0x84, 0xf7, 0x0e, 0x00, 0xff};
        CASN1Sequence publicKey;
        publicKey.addElement(CASN1Object(0x03, UUCByteArray(keyBytes, sizeof(keyBytes))));
        fields.addElement(publicKey);
        CCertificateInfo withoutExtensions(fields);
        if (withoutExtensions.getExtensions().size() != 0)
            throw std::runtime_error("Public key interpreted as extensions");
        CASN1Sequence extensions;
        UUCByteArray encodedExtensions;
        extensions.toByteArray(encodedExtensions);
        fields.addElement(CASN1Object(0xa3, encodedExtensions));
        CCertificateInfo withExtensions(fields);
        if (withExtensions.getExtensions().size() != 1)
            throw std::runtime_error("Explicit extension wrapper lost");
        std::cout << "ASN1_LENGTH_CHECKS=8 CERTIFICATE_EXTENSION_CHECKS=3\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    } catch (...) {
        std::cerr << "ASN.1 length parsing failed\n";
        return 1;
    }
}
