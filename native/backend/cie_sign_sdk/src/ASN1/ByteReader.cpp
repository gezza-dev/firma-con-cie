// SPDX-License-Identifier: BSD-3-Clause
#include "ByteReader.h"
#include <algorithm>
#include <climits>
#include <cstring>
#include <stdexcept>

CieSdkByteReader::CieSdkByteReader(const UUCByteArray& bytes)
{
    if (bytes.getLength() > UINT_MAX) throw std::length_error("ASN.1 input too large");
    if (bytes.getLength()) bytes_.assign(bytes.getContent(), bytes.getContent() + bytes.getLength());
}
CieSdkByteReader::CieSdkByteReader(const BYTE* bytes, int length)
{
    if (length < 0 || (!bytes && length)) throw std::invalid_argument("Invalid ASN.1 input");
    if (length) bytes_.assign(bytes, bytes + length);
}
unsigned int CieSdkByteReader::getPosition() { return static_cast<unsigned int>(cursor_); }
void CieSdkByteReader::setPosition(unsigned int position)
{
    if (position > bytes_.size()) throw std::out_of_range("ASN.1 cursor outside input");
    cursor_ = position;
}
unsigned int CieSdkByteReader::read(BYTE* output, unsigned int length)
{
    if (!output && length) throw std::invalid_argument("Missing ASN.1 output");
    const auto count = std::min<std::size_t>(length, bytes_.size() - cursor_);
    if (count) std::memcpy(output, bytes_.data() + cursor_, count);
    cursor_ += count;
    return static_cast<unsigned int>(count);
}
unsigned int CieSdkByteReader::read(UUCByteArray& output)
{
    const auto count = bytes_.size() - cursor_;
    if (count) output.append(bytes_.data() + cursor_, static_cast<unsigned int>(count));
    cursor_ = bytes_.size();
    return static_cast<unsigned int>(count);
}
void CieSdkByteReader::mark() { checkpoints_.push_back(cursor_); }
void CieSdkByteReader::releaseMark() { if (!checkpoints_.empty()) checkpoints_.pop_back(); }
void CieSdkByteReader::reset()
{
    if (!checkpoints_.empty()) { cursor_ = checkpoints_.back(); checkpoints_.pop_back(); }
}
