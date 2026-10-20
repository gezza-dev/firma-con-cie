#pragma once

#include "disigonsdk.h"
#include <stdarg.h>

#define MAX_LOG_SIZE			5000

#define LOG_TYPE_ERROR			1
#define LOG_TYPE_WARNING		2
#define LOG_TYPE_MESSAGE		3
#define LOG_TYPE_DEBUG			4

// Avoid interposing GLib's g_log function when GTK loads the SDK.
#define DECLARE_LOG UUCLogger cie_sdk_logger
#define USE_LOG extern UUCLogger cie_sdk_logger
#define SET_LOG_FILE(file) cie_sdk_logger.setLogFile(file)
#define SET_LOG_LEVEL(level) cie_sdk_logger.setLogLevel(level)

#define LOG_MSG(params) ((void)0)
#define LOG_ERR(params) ((void)0)
#define LOG_WAR(params) ((void)0)
#define LOG_DBG(params) ((void)0)



class UUCLogger
{
public:
	UUCLogger(void);
	UUCLogger(const char* szLogFileName);
	virtual ~UUCLogger(void);

	virtual void logMessage(const unsigned int nID, const char *szModuleName, const char* szMsg, ...);
	virtual void logWarning(const unsigned int nID, const char *szModuleName, const char* szMsg, ...);
	virtual void logError(const unsigned int nID, const char *szModuleName, const char* szMsg, ...);
	virtual void logDebug(const unsigned int nID, const char *szModuleName, const char* szMsg, ...);

	virtual void setLogFile(const char* szLogFileName);
	virtual void setLogLevel(int logLevel);
private:
	void log(const unsigned int nType, const char *szMsg, const unsigned int nID, const char *szModuleName);
	void log(const unsigned int nType, const char* szMsg, const unsigned int nID, const char *szModuleName, va_list args);

	char m_szLogFileName[MAX_PATH];
	int m_nLogLevel;
	char m_szBuffer[MAX_LOG_SIZE];
};
