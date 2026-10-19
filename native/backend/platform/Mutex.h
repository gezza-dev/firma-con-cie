// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <mutex>
class CSyncroMutex {
    std::recursive_mutex mutex;
public:
    void Create() {}
    void Create(const char*) {}
    void Lock() { mutex.lock(); }
    void Unlock() { mutex.unlock(); }
};
class CSyncroLocker {
    CSyncroMutex& mutex;
public:
    explicit CSyncroLocker(CSyncroMutex& value) : mutex(value) { mutex.Lock(); }
    ~CSyncroLocker() { mutex.Unlock(); }
    CSyncroLocker(const CSyncroLocker&) = delete;
    CSyncroLocker& operator=(const CSyncroLocker&) = delete;
};
