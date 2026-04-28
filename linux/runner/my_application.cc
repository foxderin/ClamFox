#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ---- Window control method channel handler ----
static void window_method_call_cb(FlMethodChannel* /*channel*/,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* name = fl_method_call_get_name(method_call);
  GtkWindow* window = self->window;
  g_autoptr(FlMethodResponse) response = nullptr;

  if (window == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "no_window", "Window not initialized", nullptr));
  } else if (g_strcmp0(name, "minimize") == 0) {
    gtk_window_iconify(window);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else if (g_strcmp0(name, "toggleMaximize") == 0) {
    if (gtk_window_is_maximized(window)) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else if (g_strcmp0(name, "isMaximized") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(gtk_window_is_maximized(window))));
  } else if (g_strcmp0(name, "close") == 0) {
    gtk_window_close(window);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else if (g_strcmp0(name, "startDrag") == 0) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkSeat* seat = gdk_display_get_default_seat(display);
    GdkDevice* pointer = gdk_seat_get_pointer(seat);
    if (pointer != nullptr) {
      gint x, y;
      GdkScreen* screen = nullptr;
      gdk_device_get_position(pointer, &screen, &x, &y);
      // Use a synthetic timestamp; X11 accepts GDK_CURRENT_TIME.
      gtk_window_begin_move_drag(window, /*button=*/1, x, y,
                                 GDK_CURRENT_TIME);
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_null()));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to method call: %s", error->message);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Custom title bar implemented in Flutter — strip GTK chrome.
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_title(window, "ClamFox");

  // Wayland fallback: KWin / Mutter ignore set_decorated(FALSE) when no CSD
  // titlebar is set, and may keep painting an SSD bar. Installing an empty
  // GtkBox as the titlebar makes GTK declare CSD ownership, which Wayland
  // compositors honour by skipping their own decoration.
  GtkWidget* empty_titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_size_request(empty_titlebar, -1, 0);
  gtk_window_set_titlebar(window, empty_titlebar);

  gtk_window_set_default_size(window, 1280, 760);
  gtk_widget_realize(GTK_WIDGET(window));

  // KWin/Mutter ignore gtk_window_set_decorated alone on X11 in many setups.
  // Use the legacy Motif WM hints protocol — it is honoured by every major WM
  // (KWin, Mutter, Xfwm, Openbox) and reliably removes server-side decorations.
#ifdef GDK_WINDOWING_X11
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window != nullptr && GDK_IS_X11_WINDOW(gdk_window)) {
    Display* display = GDK_WINDOW_XDISPLAY(gdk_window);
    Window xwindow = GDK_WINDOW_XID(gdk_window);
    Atom motif_atom = XInternAtom(display, "_MOTIF_WM_HINTS", False);
    struct {
      unsigned long flags;
      unsigned long functions;
      unsigned long decorations;
      long input_mode;
      unsigned long status;
    } hints = {2 /* MWM_HINTS_DECORATIONS */, 0, 0, 0, 0};
    XChangeProperty(display, xwindow, motif_atom, motif_atom, 32,
                    PropModeReplace, reinterpret_cast<unsigned char*>(&hints),
                    5);
  }
#endif

  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Register a method channel for custom window controls.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "ai.clamfox/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, window_method_call_cb,
                                            self, nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

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
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
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

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
