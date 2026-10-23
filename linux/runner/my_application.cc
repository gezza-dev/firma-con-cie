#include "my_application.h"
#include "text_scaling.h"
#include "window_sizing.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Traditional X11 decorations draw the GtkWindow title themselves. Keep that
// caption empty even if Flutter updates the application-switcher description.
static void clear_caption_title(GObject* object, GParamSpec*, gpointer) {
  GtkWindow* window = GTK_WINDOW(object);
  if (g_strcmp0(gtk_window_get_title(window), "") != 0) {
    gtk_window_set_title(window, "");
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  g_autoptr(GError) icon_error = nullptr;
  g_autoptr(GdkPixbuf) icon = gdk_pixbuf_new_from_resource(
      "/it/giancarloezza/cieid/cie-id.png", &icon_error);
  if (icon != nullptr) {
    gtk_window_set_icon(window, icon);
  } else {
    g_warning("Could not load Firma con CIE window icon: %s", icon_error->message);
  }

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    // An explicit empty custom widget prevents GTK from copying the window
    // title into the visible header, including after Flutter title updates.
    gtk_header_bar_set_custom_title(header_bar, gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
    // GTK header bars do not render GtkWindow's icon automatically. Use the
    // embedded asset at a logical size so GTK applies the display scale once.
    g_autoptr(GBytes) title_icon_bytes = g_resources_lookup_data(
        "/it/giancarloezza/cieid/cie-id.png", G_RESOURCE_LOOKUP_FLAGS_NONE, nullptr);
    if (title_icon_bytes != nullptr) {
      g_autoptr(GIcon) title_icon = g_bytes_icon_new(title_icon_bytes);
      GtkWidget* image = gtk_image_new_from_gicon(title_icon, GTK_ICON_SIZE_LARGE_TOOLBAR);
      gtk_image_set_pixel_size(GTK_IMAGE(image), 24);
      gtk_widget_set_margin_start(image, 6);
      gtk_widget_set_margin_end(image, 6);
      gtk_widget_set_valign(image, GTK_ALIGN_CENTER);
      gtk_header_bar_pack_start(header_bar, image);
      gtk_widget_show(image);
    }
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "");
    g_signal_connect(window, "notify::title", G_CALLBACK(clear_caption_title), nullptr);
  }

  cie_window_sizing_attach(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // GTK resolves the desktop's logical font DPI independently of display DPI.
  // Keep the channel alive for the view and stop its settings observer on exit.
  g_object_set_data_full(
      G_OBJECT(view), "cie-text-scaling",
      cie_text_scaling_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),
                           gtk_widget_get_screen(GTK_WIDGET(view))),
      g_object_unref);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  // Installed desktop shells resolve this name through the hicolor theme.
  // The embedded pixbuf remains the fallback for unpacked/X11 bundles.
  gtk_window_set_default_icon_name(APPLICATION_ID);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("Firma con CIE");

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
