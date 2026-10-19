/*
 *  PdfSignatureGenerator.h
 *  SignPoDoFo
 *
 *  Created by svp on 26/05/12.
 *  Copyright 2012 __MyCompanyName__. All rights reserved.
 *
 */

#ifndef _PDFSIGNATUREGENERATOR_H_
#define _PDFSIGNATUREGENERATOR_H_

#include "UUCByteArray.h"
#include <memory>

class PdfSignatureGenerator
{
public:
	PdfSignatureGenerator();
	
	virtual ~PdfSignatureGenerator();
	
	int Load(const char* pdf, int len);
	
	void InitSignature(int pageIndex, const char* szReason, const char* szReasonLabel, const char* szName, const char* szNameLabel, const char* szLocation, const char* szLocationLabel, const char* szFieldName, const char* szSubFilter);
	
	void InitSignature(int pageIndex, float left, float bottom, float width, float height, const char* szReason, const char* szReasonLabel, const char* szName, const char* szNameLabel, const char* szLocation, const char* szLocationLabel, const char* szFieldName, const char* szSubFilter);
	
	void InitSignature(int pageIndex, float left, float bottom, float width, float height, const char* szReason, const char* szReasonLabel, const char* szName, const char* szNameLabel, const char* szLocation, const char* szLocationLabel, const char* szFieldName, const char* szSubFilter, const char* szImagePath, const char* szDescription, const char* szGraphometricData, const char* szVersion);
	
	void GetBufferForSignature(UUCByteArray& toSign);
	
	void SetSignature(const char* signature, int len);
	
	void GetSignedPdf(UUCByteArray& signature);
	
	void AddFont(const char* szFontName, const char* szFontPath);
	
	const double getWidth(int pageIndex);
	
	const double getHeight(int pageIndex);
	
private:
    struct State;
    std::unique_ptr<State> state_;

};

#endif // _PDFSIGNATUREGENERATOR_H_
