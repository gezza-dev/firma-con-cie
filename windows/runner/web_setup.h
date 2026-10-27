// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <atomic>
#include <string>
#include <mutex>
#include "browser_inventory.h"
class WebSetupChannel {
 public:
  WebSetupChannel(flutter::BinaryMessenger* messenger,HWND owner);
 private:
  struct Job {std::atomic<DWORD> code{STILL_ACTIVE};};
  std::shared_ptr<Job> job_;
  std::shared_ptr<Job> package_job_;
  struct BrowserJob {
    std::atomic<bool> pending{true};
    std::mutex mutex;
    cie_browser::Inventory inventory;
  };
  std::shared_ptr<BrowserJob> browser_job_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
