// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <map>
#include <string>
#include <cstring>
#include <functional>
#include <stdexcept>
#ifndef POS
#define POS void*
#endif

// Shared implementation ensures SDK and middleware properties use the same ABI.
namespace cie {
class StringTable {
    std::map<std::string, std::string> values_;
    std::map<std::string, std::string>::iterator cursor_;
public:
    StringTable();
    explicit StringTable(int initialCapacity);
    StringTable(int initialCapacity, float loadFactor);
    StringTable(const StringTable& other) : values_(other.values_), cursor_(values_.end()) {}
    StringTable& operator=(const StringTable& other) {
        if (this != &other) { values_ = other.values_; cursor_ = values_.end(); }
        return *this;
    }
    virtual ~StringTable() = default;
    unsigned int size() const;
    bool isEmpty() const;
    bool containsKey(char* const& key) const;
    virtual bool get(char*& key, char*& value) const;
    virtual void put(char* const& key, char* const& value);
    virtual bool remove(char* const& key);
    void remove();
    virtual void removeAll();
    POS getFirstPosition();
    POS getNextEntry(POS position, char*& key, char*& value);
    static unsigned long getHash(const char* key);
protected:
    virtual unsigned long getHashValue(char* const& key) const;
    virtual bool equal(char* const& left, char* const& right) const;
};

inline StringTable::StringTable() : cursor_(values_.end()) {}
inline StringTable::StringTable(int) : StringTable() {}
inline StringTable::StringTable(int, float) : StringTable() {}
inline unsigned int StringTable::size() const { return static_cast<unsigned int>(values_.size()); }
inline bool StringTable::isEmpty() const { return values_.empty(); }
inline bool StringTable::containsKey(char* const& key) const { return key && values_.find(key) != values_.end(); }
inline bool StringTable::get(char*& key, char*& value) const
{
    if (!key) return false;
    const auto item = values_.find(key);
    if (item == values_.end()) return false;
    // Returned strings are borrowed and remain valid until this entry changes.
    key = const_cast<char*>(item->first.c_str());
    value = const_cast<char*>(item->second.c_str());
    return true;
}
inline void StringTable::put(char* const& key, char* const& value)
{
    if (!key || !value) throw std::invalid_argument("Null string table entry");
    // Copy before updating: callers may pass strings borrowed from this table.
    std::string ownedKey(key), ownedValue(value);
    values_[ownedKey] = ownedValue;
}
inline bool StringTable::remove(char* const& key) { return key && values_.erase(key) != 0; }
inline void StringTable::remove() { removeAll(); }
inline void StringTable::removeAll() { values_.clear(); cursor_ = values_.end(); }
inline POS StringTable::getFirstPosition() { cursor_ = values_.begin(); return cursor_ == values_.end() ? nullptr : &cursor_; }
inline POS StringTable::getNextEntry(POS position, char*& key, char*& value)
{
    if (position != &cursor_ || cursor_ == values_.end()) { key = value = nullptr; return nullptr; }
    key = const_cast<char*>(cursor_->first.c_str()); value = const_cast<char*>(cursor_->second.c_str());
    ++cursor_;
    return cursor_ == values_.end() ? nullptr : &cursor_;
}
inline unsigned long StringTable::getHash(const char* key) { return key ? std::hash<std::string>{}(key) : 0; }
inline unsigned long StringTable::getHashValue(char* const& key) const { return getHash(key); }
inline bool StringTable::equal(char* const& left, char* const& right) const { return left && right ? std::strcmp(left, right) == 0 : left == right; }

}
using UUCStringTable = cie::StringTable;
