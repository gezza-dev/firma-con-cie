// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "cie_enrollment_types.h"
#include <vector>
#include <cstring>
#include <stdexcept>
namespace cie {
// Public material is stored only after authentication and strict SOD checking.
// Binary, bounded and versioned; no prefix, PIN, reader or paths are serialized.
inline std::vector<uint8_t> encodeEnrollment(const CieEnrollmentMaterial& m){
 size_t n=0;while(n<sizeof(m.fullName)&&m.fullName[n])++n;
 if(m.size!=sizeof(m)||m.version!=2||!n||n>=sizeof(m.fullName)||!m.certificateLength||m.certificateLength>8192)throw std::runtime_error("enrollment_invalid_material");
 std::vector<uint8_t> out{'C','I','E','P','U','B','2',0,uint8_t(n>>8),uint8_t(n),uint8_t(m.certificateLength>>8),uint8_t(m.certificateLength)};
 out.insert(out.end(),m.fullName,m.fullName+n);out.insert(out.end(),m.certificate,m.certificate+m.certificateLength);return out;
}
inline CieEnrollmentMaterial decodeEnrollment(const std::vector<uint8_t>& data){
 CieEnrollmentMaterial m{};m.size=sizeof(m);m.version=2;
 if(data.size()<12||std::memcmp(data.data(),"CIEPUB2",8))throw std::runtime_error("enrollment_invalid_record");
 size_t n=(size_t(data[8])<<8)|data[9],c=(size_t(data[10])<<8)|data[11];
 if(!n||n>=sizeof(m.fullName)||!c||c>8192||data.size()!=12+n+c)throw std::runtime_error("enrollment_invalid_record");
 for(size_t i=12;i<12+n;++i)if(data[i]<32||data[i]==127)throw std::runtime_error("enrollment_invalid_name");
 std::memcpy(m.fullName,data.data()+12,n);std::memcpy(m.certificate,data.data()+12+n,c);m.certificateLength=c;return m;
}
}
