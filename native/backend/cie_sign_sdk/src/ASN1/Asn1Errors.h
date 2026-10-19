// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstring>
#include <string>

class CASN1Exception {
    std::string message_;
public:
    const char* m_lpszMsg;
    explicit CASN1Exception(const char* message) : message_(message ? message : ""), m_lpszMsg(message_.c_str()) {}
    CASN1Exception(const CASN1Exception& other) : message_(other.message_), m_lpszMsg(message_.c_str()) {}
    CASN1Exception& operator=(const CASN1Exception& other) {
        message_ = other.message_; m_lpszMsg = message_.c_str(); return *this;
    }
    virtual ~CASN1Exception() = default;
    virtual bool GetErrorMessage(char* output, unsigned int capacity) {
        if (!output || capacity <= message_.size()) return false;
        std::memcpy(output, message_.c_str(), message_.size() + 1);
        return true;
    }
};
class CASN1ParsingException : public CASN1Exception {
public: CASN1ParsingException() : CASN1Exception("Invalid ASN.1 encoding") {}
};
class CASN1ObjectNotFoundException : public CASN1Exception {
public: explicit CASN1ObjectNotFoundException(const char* name) : CASN1Exception(name) {}
};
class CASN1BadObjectIdException : public CASN1Exception {
public: explicit CASN1BadObjectIdException(const char* name) : CASN1Exception(name) {}
};
class CBadContentTypeException : public CASN1Exception {
public: CBadContentTypeException() : CASN1Exception("Invalid ASN.1 content type") {}
};
