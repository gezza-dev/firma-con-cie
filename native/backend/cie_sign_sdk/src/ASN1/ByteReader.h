// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "UUCByteArray.h"
#include <cstddef>
#include <vector>

// An owned byte sequence with a cursor and a LIFO stack of parser checkpoints.
class CieSdkByteReader {
    std::vector<BYTE> bytes_;
    std::size_t cursor_ = 0;
    std::vector<std::size_t> checkpoints_;
public:
    explicit CieSdkByteReader(const UUCByteArray& bytes);
    CieSdkByteReader(const BYTE* bytes, int length);
    virtual ~CieSdkByteReader() = default;
    unsigned int getPosition();
    void setPosition(unsigned int position);
    unsigned int read(BYTE* output, unsigned int length);
    unsigned int read(UUCByteArray& output);
    void mark();
    void reset();
    void releaseMark();
};
using UUCBufferedReader = CieSdkByteReader;
