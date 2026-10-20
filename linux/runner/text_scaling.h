// SPDX-License-Identifier: BSD-3-Clause
#ifndef CIE_LINUX_TEXT_SCALING_H_
#define CIE_LINUX_TEXT_SCALING_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(CieTextScaling, cie_text_scaling, CIE, TEXT_SCALING, GObject)

// The owner must release this object before its Flutter messenger is destroyed.
CieTextScaling* cie_text_scaling_new(FlBinaryMessenger* messenger,
                                    GdkScreen* screen);

#endif  // CIE_LINUX_TEXT_SCALING_H_
