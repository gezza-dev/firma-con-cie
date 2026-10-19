#include "CIEVerify.h"
#include <memory>
#include <cstring>
#include "log.h"
#include "../LOGGER/Logger.h"

using namespace CieIDLogger;

CIEVerify::CIEVerify()
{

}

CIEVerify::~CIEVerify() = default;

long CIEVerify::verify(const char* input_file, VERIFY_RESULT* verifyResult, const char* proxy_address, int proxy_port, const char* userPass)
{

    if (!verifyResult) return DISIGON_ERROR_INVALID_SIGOPT;
    if (!input_file || !*input_file || std::strlen(input_file) >= sizeof(verifyResult->szInputFile))
        return DISIGON_ERROR_INVALID_FILE;
    try {
        std::unique_ptr<void, decltype(&disigon_verify_cleanup)> context(
            disigon_verify_init(), disigon_verify_cleanup);
        if (!context) return DISIGON_ERROR_UNEXPECTED;
        auto set = [&](int option, void* value) {
            long result = disigon_verify_set(context.get(), option, value);
            if (result) throw result;
        };
        set(DISIGON_OPT_INPUTFILE, (void*)input_file);
        set(DISIGON_OPT_INPUTFILE_TYPE, (void*)DISIGON_FILETYPE_AUTO);
        set(DISIGON_OPT_VERIFY_REVOCATION, (void*)1);
        if (proxy_address && *proxy_address) {
            if (proxy_port <= 0 || proxy_port > 65535 || std::strlen(proxy_address) >= MAX_PATH)
                return DISIGON_ERROR_INVALID_SIGOPT;
            set(DISIGON_OPT_PROXY, (void*)proxy_address);
            set(DISIGON_OPT_PROXY_PORT, (void*)(long)proxy_port);
            if (userPass && *userPass) set(DISIGON_OPT_PROXY_USRPASS, (void*)userPass);
        }
        return disigon_verify_verify(context.get(), verifyResult);
    } catch (long error) {
        return error;
    } catch (...) {
        return DISIGON_ERROR_UNEXPECTED;
    }
}


long CIEVerify::get_file_from_p7m(const char* input_file,const char* output_file) {
    std::unique_ptr<void,decltype(&disigon_verify_cleanup)> context(disigon_verify_init(),disigon_verify_cleanup);
    if(!context) return DISIGON_ERROR_UNEXPECTED;
    for(auto item : {std::pair<int,void*>{DISIGON_OPT_INPUTFILE,const_cast<char*>(input_file)},
        {DISIGON_OPT_OUTPUTFILE,const_cast<char*>(output_file)},
        {DISIGON_OPT_INPUTFILE_TYPE,reinterpret_cast<void*>(DISIGON_FILETYPE_AUTO)}}) {
        auto status=disigon_verify_set(context.get(),item.first,item.second);if(status)return status;
    }
    return disigon_get_file_from_p7m(context.get());
}
