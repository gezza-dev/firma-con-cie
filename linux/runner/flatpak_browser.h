// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

// Fixed companion API only: no shell, paths, host spawning or PIN operations.
GObject* cie_flatpak_browser_new(FlBinaryMessenger* messenger, GDBusConnection* bus);
