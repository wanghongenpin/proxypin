#pragma once

namespace crash_handler {

// Installs handlers for unhandled SEH exceptions and C++ terminate.
// - Generates a minidump to the exe directory by default.
// - Shows a MessageBox with the exception code + dump path.
// Call as early as possible in wWinMain.
void Install(const wchar_t* app_name);

}  // namespace crash_handler

