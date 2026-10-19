#pragma once

#include "cie_platform.h"

class CCardContext
{
public:
	SCARDCONTEXT hContext;

	CCardContext(void);
	~CCardContext(void);

	operator SCARDCONTEXT();
	void validate();
	void renew();

private:
	void getContext();

};
