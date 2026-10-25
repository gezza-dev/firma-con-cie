#include "my_application.h"
#include <X11/Xlib.h>

int main(int argc, char** argv) {
  // Older Xlib requires this before GTK/Flutter starts rendering threads.
  (void)XInitThreads();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
