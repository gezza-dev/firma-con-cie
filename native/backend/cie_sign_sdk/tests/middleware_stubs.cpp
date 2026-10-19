// Symbols provided by the middleware when the SDK is used by the app.
// No-card integration tests must fail if a card/cache operation is attempted.
class CLog;
#include "log.h"
#include <cryptopp/cryptlib.h>
#include <cryptopp/integer.h>
#include <stdexcept>
#include <string>

CLog Log;

void GetPublicKeyFromCert(CryptoPP::BufferedTransformation&,
    CryptoPP::BufferedTransformation&, CryptoPP::BufferedTransformation&, CryptoPP::Integer&)
{
    throw std::logic_error("Card SOD validation requires the middleware");
}

void notifyCardNotRegistered(const char*)
{
    throw std::logic_error("Card registration requires the middleware");
}

int decrypt(std::string&, std::string&)
{
    throw std::logic_error("Card cache decryption requires the middleware");
}
