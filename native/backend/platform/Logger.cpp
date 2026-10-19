// SPDX-License-Identifier: BSD-3-Clause
// Intentionally silent: legacy callers log APDU payloads and authentication
// internals. Enable diagnostic events only after introducing a redacted API.
#include "../cie-pkcs11/LOGGER/Logger.h"
namespace CieIDLogger {
Logger* Logger::m_Instance = nullptr;
Logger::Logger() {}
Logger::~Logger() {}
Logger* Logger::getInstance() throw() { static Logger instance; return &instance; }
void Logger::updateLogLevel(LogLevel) {}
void Logger::enableLog() {}
void Logger::disableLog() {}
void Logger::updateLogType(LogType) {}
void Logger::enableConsoleLogging() {}
void Logger::enableFileLogging() {}
void Logger::debug(const char*, ...) throw() {}
void Logger::debug(std::string&) throw() {}
void Logger::debug(std::ostringstream&) throw() {}
void Logger::info(const char*, ...) throw() {}
void Logger::info(std::string&) throw() {}
void Logger::info(std::ostringstream&) throw() {}
int Logger::error(const char*, ...) throw() { return 0; }
int Logger::error(std::string&) throw() { return 0; }
int Logger::error(std::ostringstream&) throw() { return 0; }
void Logger::buffer(uint8_t*, size_t) throw() {}
}
