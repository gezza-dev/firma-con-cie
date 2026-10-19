// SPDX-License-Identifier: BSD-3-Clause
// Do not format legacy log arguments: they may contain PINs or SDK options
// represented as pointer-sized integers rather than C strings.
#include "UUCLogger.h"
logFunc pfnCrashliticsLog = nullptr;
UUCLogger::UUCLogger() : m_nLogLevel(0) {}
UUCLogger::UUCLogger(const char*) : m_nLogLevel(0) {}
UUCLogger::~UUCLogger() {}
void UUCLogger::setLogFile(const char*) {}
void UUCLogger::setLogLevel(int) {}
void UUCLogger::logMessage(unsigned int, const char*, const char*, ...) {}
void UUCLogger::logWarning(unsigned int, const char*, const char*, ...) {}
void UUCLogger::logError(unsigned int, const char*, const char*, ...) {}
void UUCLogger::logDebug(unsigned int, const char*, const char*, ...) {}
