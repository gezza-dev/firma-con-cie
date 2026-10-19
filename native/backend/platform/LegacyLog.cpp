// SPDX-License-Identifier: BSD-3-Clause
class CLog;
#include "../cie_sign_sdk/src/Util/log.h"
bool FunctionLog = false;
unsigned int GlobalDepth = 0;
void initLog(const char*, const char*, const char*) {}
CLog::CLog() : LogCount(0), Initialized(false), Enabled(false), FunctionLog(false), LogParam(false), ModuleNum(0), FirstLog(false), _stack_logged(false) {}
CLog::~CLog() {}
void CLog::init() {}
DWORD CLog::write(const char*, ...) { return 0; }
void CLog::writePure(const char*, ...) {}
void CLog::writeBinData(uint8_t*, size_t) {}
void CLog::writeModuleInfo() {}
void CLog::dumpErr() {}
