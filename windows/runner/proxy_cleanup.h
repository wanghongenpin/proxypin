#ifndef RUNNER_PROXY_CLEANUP_H_
#define RUNNER_PROXY_CLEANUP_H_

// Disables the current user's Internet Settings proxy and clears related
// values, then refreshes WinInet so the change takes effect immediately.
void ClearSystemProxy();

#endif  // RUNNER_PROXY_CLEANUP_H_

