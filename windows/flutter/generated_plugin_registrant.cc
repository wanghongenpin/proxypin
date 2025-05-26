//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <flutter_desktop_context_menu/flutter_desktop_context_menu_plugin.h>
#include <flutter_js/flutter_js_plugin.h>
#include <proxy_manager/proxy_manager_plugin.h>
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <share_plus/share_plus_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <vclibs/vclibs_plugin_c_api.h>
#include <win32audio/win32audio_plugin_c_api.h>
#include <window_manager/window_manager_plugin.h>
#include <windows_single_instance/windows_single_instance_plugin.h>
#include <zstandard_windows/zstandard_windows_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  DesktopMultiWindowPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopMultiWindowPlugin"));
  FlutterDesktopContextMenuPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterDesktopContextMenuPlugin"));
  FlutterJsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterJsPlugin"));
  ProxyManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ProxyManagerPlugin"));
  ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  SharePlusWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SharePlusWindowsPluginCApi"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  VclibsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("VclibsPluginCApi"));
  Win32audioPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("Win32audioPluginCApi"));
  WindowManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowManagerPlugin"));
  WindowsSingleInstancePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowsSingleInstancePlugin"));
  ZstandardWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ZstandardWindowsPluginCApi"));
}
