#include "proxy_cleanup.h"

#include <windows.h>
#include <wininet.h>

namespace {

constexpr wchar_t kInternetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

}  // namespace

void ClearSystemProxy() {
  HKEY internet_settings = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0,
                      KEY_SET_VALUE, &internet_settings) != ERROR_SUCCESS) {
    return;
  }

  DWORD disabled = 0;
  ::RegSetValueExW(internet_settings, L"ProxyEnable", 0, REG_DWORD,
                   reinterpret_cast<const BYTE*>(&disabled), sizeof(disabled));
  ::RegDeleteValueW(internet_settings, L"ProxyServer");
  ::RegDeleteValueW(internet_settings, L"ProxyOverride");
  ::RegCloseKey(internet_settings);

  ::InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  ::InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

