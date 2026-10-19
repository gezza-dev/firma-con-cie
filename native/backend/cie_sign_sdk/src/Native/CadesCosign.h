// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <vector>
#include <cstddef>
namespace cie::cades {
using Bytes=std::vector<unsigned char>;
// Strict attached id-data CMS, all signatures cryptographically valid; no trust/network check.
Bytes canonical(const void* data,size_t size);
Bytes content(const Bytes& cms);
unsigned count(const Bytes& cms);
Bytes merge(const Bytes& original,const Bytes& fresh);
bool preserves(const Bytes& original,const Bytes& result);
}
