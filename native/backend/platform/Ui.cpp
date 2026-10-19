// SPDX-License-Identifier: BSD-3-Clause
// Authentication errors are returned through the bridge; the backend must not
// launch another app or send document/card identifiers over a local socket.
void showUI(const char*) {}
void notifyPINLocked() {}
void notifyPINWrong(int) {}
void notifyCardNotRegistered(const char*) {}
