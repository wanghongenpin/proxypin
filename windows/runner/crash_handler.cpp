#include "crash_handler.h"

#include <windows.h>

#include <cstdlib>
#include <exception>
#include <string>
#include <cstring>  // _dupenv_s
#include <cctype>

// Optional: symbolize stack addresses (no dump writing).
#include <DbgHelp.h>
#pragma comment(lib, "Dbghelp.lib")

#include <Psapi.h>
#pragma comment(lib, "Psapi.lib")

#include <mutex>

#pragma intrinsic(memcpy)

namespace crash_handler {

static std::wstring g_app_name = L"App";

// If true, we'll try to continue execution for a very small set of exceptions
// that are generally recoverable. For most crashes (e.g., access violations),
// continuing is unsafe and will likely crash again.
static bool g_try_continue = false;

// If true, after showing the crash dialog we keep the process alive (hang)
// so it doesn't disappear. This is NOT recovery; it just prevents auto-close.
//
// Default: false (terminate after dialog). You can enable keep-alive via env var:
//  KEEP_ALIVE_AFTER_CRASH=1
static bool g_keep_alive_after_crash = false;

// Exit code used when terminating after a crash dialog.
static const UINT g_crash_exit_code = 0xDEAD;

// Prevent re-entrancy (crash while handling a crash).
static volatile LONG g_in_handler = 0;

// Forward declarations (MSVC requires a declaration before first use).
static void EnsureSymbolizerInitialized();
static std::wstring GetExeDir();
static std::wstring SymbolizeAddress(void* addr);
static std::wstring DescribeAddressFallback(void* addr);

// Read env var in an MSVC-safe way. Returns empty string if unset.
static std::string GetEnvVar(const char* name) {
  if (!name || !*name) return {};
  char* buf = nullptr;
  size_t len = 0;
  if (_dupenv_s(&buf, &len, name) != 0 || !buf) return {};
  std::string out(buf);
  free(buf);
  return out;
}

// Build an environment variable name from the wide `app_name`.
// Result will look like: UPPERCASED_APPNAME_KEEP_ALIVE_AFTER_CRASH
// Non-alphanumeric characters in the app name are replaced with '_'.
static std::string MakeEnvVarNameFromAppName(const std::wstring& app_name) {
  if (app_name.empty()) return std::string("APP_KEEP_ALIVE_AFTER_CRASH");

  int required = ::WideCharToMultiByte(CP_ACP, 0, app_name.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (required <= 0) return std::string("APP_KEEP_ALIVE_AFTER_CRASH");

  std::string name(required, '\0');
  ::WideCharToMultiByte(CP_ACP, 0, app_name.c_str(), -1, &name[0], required, nullptr, nullptr);
  // remove terminating null if present
  if (!name.empty() && name.back() == '\0') name.pop_back();

  for (char &c : name) {
    unsigned char uc = static_cast<unsigned char>(c);
    if (std::isalnum(uc)) {
      c = static_cast<char>(std::toupper(uc));
    } else {
      c = '_';
    }
  }

  name.append("_KEEP_ALIVE_AFTER_CRASH");
  return name;
}

static void AppendHex(std::wstring& out, const wchar_t* prefix, uintptr_t value) {
  wchar_t buf[64];
#if defined(_WIN64)
  std::swprintf(buf, 64, L"%s0x%016llX", prefix ? prefix : L"", static_cast<unsigned long long>(value));
#else
  std::swprintf(buf, 64, L"%s0x%08lX", prefix ? prefix : L"", static_cast<unsigned long>(value));
#endif
  out.append(buf);
}

static void AppendU64(std::wstring& out, const wchar_t* prefix, unsigned long long value) {
  wchar_t buf[64];
  std::swprintf(buf, 64, L"%s%llu", prefix ? prefix : L"", value);
  out.append(buf);
}

static std::wstring SysMsg(DWORD code) {
  wchar_t* buf = nullptr;
  DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
  DWORD len = ::FormatMessageW(flags, nullptr, code, 0 /*LANG_USER_DEFAULT*/, (LPWSTR)&buf, 0, nullptr);
  if (len == 0 || !buf) return L"";
  std::wstring msg(buf, buf + len);
  ::LocalFree(buf);
  while (!msg.empty() && (msg.back() == L'\r' || msg.back() == L'\n' || msg.back() == L' ')) msg.pop_back();
  return msg;
}

static const wchar_t* ExceptionName(DWORD code) {
  switch (code) {
    case EXCEPTION_ACCESS_VIOLATION:
      return L"EXCEPTION_ACCESS_VIOLATION";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
      return L"EXCEPTION_ARRAY_BOUNDS_EXCEEDED";
    case EXCEPTION_BREAKPOINT:
      return L"EXCEPTION_BREAKPOINT";
    case EXCEPTION_DATATYPE_MISALIGNMENT:
      return L"EXCEPTION_DATATYPE_MISALIGNMENT";
    case EXCEPTION_FLT_DIVIDE_BY_ZERO:
      return L"EXCEPTION_FLT_DIVIDE_BY_ZERO";
    case EXCEPTION_ILLEGAL_INSTRUCTION:
      return L"EXCEPTION_ILLEGAL_INSTRUCTION";
    case EXCEPTION_IN_PAGE_ERROR:
      return L"EXCEPTION_IN_PAGE_ERROR";
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
      return L"EXCEPTION_INT_DIVIDE_BY_ZERO";
    case EXCEPTION_STACK_OVERFLOW:
      return L"EXCEPTION_STACK_OVERFLOW";
    default:
      return L"UNKNOWN_SEH_EXCEPTION";
  }
}

static void Show(const std::wstring& title, const std::wstring& msg) {
  ::MessageBoxW(nullptr, msg.c_str(), title.c_str(), MB_OK | MB_ICONERROR | MB_SYSTEMMODAL);
}

static void KeepProcessAlive() {
  // After a fatal crash, continuing execution is unsafe.
  // We intentionally "hang" the process here.
  for (;;) {
    ::Sleep(1000);
  }
}

static void TerminateNow() {
  // Unconditional exit: do not rely on other threads or the message loop.
  ::TerminateProcess(::GetCurrentProcess(), g_crash_exit_code);
}

struct DialogPayload {
  std::wstring title;
  std::wstring msg;
};

static DWORD WINAPI DialogThreadProc(LPVOID p) {
  DialogPayload* payload = reinterpret_cast<DialogPayload*>(p);
  // Best-effort: show dialog.
  Show(payload->title, payload->msg);
  delete payload;

  // After the dialog is dismissed, either terminate or keep the process alive.
  if (g_keep_alive_after_crash) {
    KeepProcessAlive();
  } else {
    TerminateNow();
  }
  return 0;
}

static void ShowAsyncAndFreeze(const std::wstring& title, const std::wstring& msg) {
  // Allocate payload on heap; crashing thread's stack may be corrupted.
  DialogPayload* payload = new DialogPayload{title, msg};

  // Create a new thread with a clean stack to show UI.
  HANDLE th = ::CreateThread(nullptr, 0, DialogThreadProc, payload, 0, nullptr);
  if (th) {
    ::CloseHandle(th);

    // Important: do NOT terminate the process here.
    // If we call TerminateProcess immediately, the dialog thread is killed before
    // MessageBoxW can display. Instead, keep this thread parked forever.
    // DialogThreadProc will terminate after the user dismisses the dialog.
    KeepProcessAlive();
  } else {
    // Fallback: show synchronously.
    Show(title, msg);
    delete payload;

    if (g_keep_alive_after_crash) {
      KeepProcessAlive();
    } else {
      TerminateNow();
    }
  }
}

static void AppendStack(std::wstring& msg) {
  void* frames[48] = {};
  USHORT n = ::RtlCaptureStackBackTrace(2, 48, frames, nullptr);
  if (n == 0) return;

  msg += L"\r\n== Stack ==\r\n";
  for (USHORT i = 0; i < n; i++) {
    const std::wstring s = SymbolizeAddress(frames[i]);

    msg += L"#";
    AppendU64(msg, L"", static_cast<unsigned long long>(i));
    msg += L" ";

    if (!s.empty()) {
      msg.append(s);
    } else {
      // Requirement: stack default doesn't show addresses; but if we can't parse/symbolize,
      // show the address so there is at least something to report.
      msg.append(DescribeAddressFallback(frames[i]));
    }

    msg += L"\r\n";
  }
}

static bool CanContinue(DWORD code) {
  // Be conservative. Most SEH exceptions mean process state is corrupted.
  // We only allow continuing for cases that are commonly used for control flow
  // or debugging.
  switch (code) {
    case EXCEPTION_BREAKPOINT:
    case EXCEPTION_SINGLE_STEP:
      return true;
    default:
      return false;
  }
}

static LONG WINAPI SehFilter(EXCEPTION_POINTERS* ep) {
  if (::InterlockedCompareExchange(&g_in_handler, 1, 0) != 0) {
    // Already handling a crash -> don't recurse.
    return EXCEPTION_EXECUTE_HANDLER;
  }

  DWORD code = ep && ep->ExceptionRecord ? ep->ExceptionRecord->ExceptionCode : 0;

  const DWORD pid = ::GetCurrentProcessId();
  const DWORD tid = ::GetCurrentThreadId();

  std::wstring title = g_app_name + L" crashed";
  std::wstring msg;
  msg.reserve(4096);

  msg += L"Unhandled Windows exception (SEH)\r\n\r\n";

  wchar_t code_hex[32];
  std::swprintf(code_hex, 32, L"0x%08lX", code);
  msg += L"Exception: ";
  msg += ExceptionName(code);
  msg += L" (";
  msg += code_hex;
  msg += L")\r\n";

  msg += L"ProcessId: ";
  AppendU64(msg, L"", pid);
  msg += L"\r\nThreadId: ";
  AppendU64(msg, L"", tid);
  msg += L"\r\n";

  if (ep && ep->ExceptionRecord) {
    const EXCEPTION_RECORD* er = ep->ExceptionRecord;

    msg += L"\r\nFault: ";
    auto fault = SymbolizeAddress(er->ExceptionAddress);
    msg += fault.empty() ? DescribeAddressFallback(er->ExceptionAddress) : fault;
    msg += L"\r\n";

    if (code == EXCEPTION_ACCESS_VIOLATION && er->NumberParameters >= 2) {
      const ULONG_PTR op = er->ExceptionInformation[0];
      const ULONG_PTR addr = er->ExceptionInformation[1];
      msg += L"AccessViolation: ";
      msg += (op == 0) ? L"READ" : (op == 1) ? L"WRITE" : (op == 8) ? L"DEP" : L"UNKNOWN";
      msg += L" at ";
      AppendHex(msg, L"", static_cast<uintptr_t>(addr));
      msg += L"\r\n";
    }

    if (code == EXCEPTION_IN_PAGE_ERROR && er->NumberParameters >= 3) {
      msg += L"InPageError: address ";
      AppendHex(msg, L"", static_cast<uintptr_t>(er->ExceptionInformation[1]));
      msg += L"  NTSTATUS ";
      AppendHex(msg, L"", static_cast<uintptr_t>(er->ExceptionInformation[2]));
      msg += L"\r\n";
    }
  }

  auto sys = SysMsg(code);
  if (!sys.empty()) {
    msg += L"\r\nSystem: ";
    msg += sys;
    msg += L"\r\n";
  }

  AppendStack(msg);

  // Tell the user whether we will attempt to continue.
  const bool will_continue = g_try_continue && CanContinue(code);
  msg += L"\r\nAction: ";
  msg += will_continue ? L"Continue execution (best-effort)" : L"Terminate";
  msg += L"\r\n";

  // Replace direct Show() with async dialog on a clean thread.
  ShowAsyncAndFreeze(title, msg);

  if (will_continue) {
    ::InterlockedExchange(&g_in_handler, 0);
    return EXCEPTION_CONTINUE_EXECUTION;
  }

  // We generally won't reach here because ShowAsyncAndFreeze freezes.
  ::InterlockedExchange(&g_in_handler, 0);
  return EXCEPTION_EXECUTE_HANDLER;
}

static void TerminateHandler() {
  if (::InterlockedCompareExchange(&g_in_handler, 1, 0) != 0) {
    std::abort();
  }

  std::wstring title = g_app_name + L" crashed";

  std::wstring msg;
  msg.reserve(2048);
  msg += L"std::terminate called (likely an uncaught C++ exception).\r\n";
  msg += L"ProcessId: ";
  AppendU64(msg, L"", ::GetCurrentProcessId());
  msg += L"\r\nThreadId: ";
  AppendU64(msg, L"", ::GetCurrentThreadId());
  msg += L"\r\n";

  AppendStack(msg);

  ShowAsyncAndFreeze(title, msg);

  // We generally won't reach here.
  std::abort();
}

static std::wstring GetExeDir() {
  wchar_t path[MAX_PATH] = {};
  DWORD n = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return L".";
  std::wstring s(path);
  size_t pos = s.find_last_of(L"\\/");
  if (pos == std::wstring::npos) return L".";
  return s.substr(0, pos);
}

static void EnsureSymbolizerInitialized() {
  static std::once_flag once;
  std::call_once(once, [] {
    HANDLE proc = ::GetCurrentProcess();

    // Make symbolization as useful as possible.
    ::SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);

    // Search exe directory first (where PDB usually lives in Debug), then current directory.
    // (No network symbol server here; keep it simple and deterministic.)
    std::wstring exe_dir = GetExeDir();
    std::wstring search = exe_dir + L";.;";
    ::SymInitializeW(proc, search.c_str(), TRUE /* invade process */);
  });
}

// Build a compact "module!symbol(file:line)" string when possible.
// If symbolization fails, return an empty string (caller may fallback to address).
static std::wstring SymbolizeAddress(void* addr) {
  EnsureSymbolizerInitialized();

  HANDLE proc = ::GetCurrentProcess();
  const DWORD64 address = static_cast<DWORD64>(reinterpret_cast<uintptr_t>(addr));

  // Module name (best-effort). Prefer querying the module that contains `addr`.
  wchar_t module_name_buf[MAX_PATH] = {};
  const wchar_t* module_name = nullptr;
  HMODULE hmod = nullptr;
  if (::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(addr), &hmod) == TRUE && hmod) {
    if (::GetModuleBaseNameW(proc, hmod, module_name_buf, MAX_PATH) > 0) {
      module_name = module_name_buf;
    }
  }

  // Function
  alignas(SYMBOL_INFO) unsigned char sym_buf[sizeof(SYMBOL_INFO) + MAX_SYM_NAME * sizeof(char)] = {};
  SYMBOL_INFO* sym = reinterpret_cast<SYMBOL_INFO*>(sym_buf);
  sym->SizeOfStruct = sizeof(SYMBOL_INFO);
  sym->MaxNameLen = MAX_SYM_NAME;

  DWORD64 disp = 0;
  const bool has_sym = ::SymFromAddr(proc, address, &disp, sym) == TRUE;
  if (!has_sym) return L"";

  // Line
  IMAGEHLP_LINEW64 line{};
  line.SizeOfStruct = sizeof(line);
  DWORD line_disp = 0;
  const bool has_line = ::SymGetLineFromAddrW64(proc, address, &line_disp, &line) == TRUE;

  std::wstring out;
  if (module_name && *module_name) {
    out.append(module_name);
    out.append(L"!");
  }

  // sym->Name is ANSI. ACP is the safest default.
  wchar_t wname[1024] = {};
  ::MultiByteToWideChar(CP_ACP, 0, sym->Name, -1, wname, 1024);
  out.append(wname);

  // Avoid raw addresses; keep only a small decimal offset (optional).
  if (disp != 0) {
    out.append(L"+");
    AppendU64(out, L"", static_cast<unsigned long long>(disp));
  }

  if (has_line && line.FileName && *line.FileName) {
    out.append(L"  (");
    out.append(line.FileName);
    out.append(L":");
    AppendU64(out, L"", static_cast<unsigned long long>(line.LineNumber));
    out.append(L")");
  }

  return out;
}

// If symbolization fails, return module+raw address (so users can still provide something).
static std::wstring DescribeAddressFallback(void* addr) {
  HANDLE proc = ::GetCurrentProcess();

  wchar_t module_name_buf[MAX_PATH] = {};
  const wchar_t* module_name = nullptr;
  HMODULE hmod = nullptr;
  if (::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(addr), &hmod) == TRUE && hmod) {
    if (::GetModuleBaseNameW(proc, hmod, module_name_buf, MAX_PATH) > 0) {
      module_name = module_name_buf;
    }
  }

  std::wstring out;
  if (module_name && *module_name) {
    out.append(module_name);
    out.append(L"+");
  }
  AppendHex(out, L"", reinterpret_cast<uintptr_t>(addr));
  return out;
}

void Install(const wchar_t* app_name) {
  if (app_name && *app_name) g_app_name = app_name;

  // Default policy: do NOT continue after an unhandled exception.
  // You can flip this to true if you really want to try continuing for
  // breakpoint/single-step exceptions.
  g_try_continue = false;

  // Default: terminate after crash dialog.
  // Set <APPNAME>_KEEP_ALIVE_AFTER_CRASH=1 to keep the process alive for debugging.
  g_keep_alive_after_crash = false;
  const std::string env_name = MakeEnvVarNameFromAppName(g_app_name);
  const std::string v = GetEnvVar(env_name.c_str());
  if (!v.empty()) {
    const char c = v[0];
    if (c == '1' || c == 't' || c == 'T' || c == 'y' || c == 'Y') {
      g_keep_alive_after_crash = true;
    }
  }

  // Prevent the OS from showing its own critical-error dialog on top of ours.
  // (Also avoids some situations where the process gets terminated after the system dialog.)
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);

  ::SetUnhandledExceptionFilter(SehFilter);
  std::set_terminate(TerminateHandler);
}

}  // namespace crash_handler

