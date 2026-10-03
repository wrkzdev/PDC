// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

// C ABI of the remote-only wallet library (pdc_wallet_core) used by the Flutter wallet over dart:ffi.
// A thin, stable wrapper over plain_wallet_api.h: strings in, strings out, no C++ types cross the boundary.
//
// Conventions
//  - Every function returns a NUL-terminated UTF-8 string allocated by the library. Release it with pdc_wallet_free().
//    Failures, including C++ exceptions, come back as a JSON error string; NULL is returned only when memory for the
//    reply itself cannot be allocated, and callers must treat NULL as an error.
//  - The strings are exactly what plain_wallet_api returns: a bare status word ("OK"), or JSON such as
//    {"id":0,"jsonrpc":"2.0","result":{...}} / {"error":{"code":"...","message":"..."}}.
//  - Arguments are borrowed for the duration of the call. NULL is treated as an empty string.
//  - The library is a process-wide singleton (like plain_wallet_api): call pdc_wallet_init() once before anything else.
//  - Calls can block for seconds (opening a wallet, building a transaction). Call them off the UI thread.
//
// This header is shared by the library, by the test stub and by the Dart binding; bump PDC_WALLET_CORE_ABI_VERSION
// whenever anything here changes.

#pragma once

#include <stdint.h>

#define PDC_WALLET_CORE_ABI_VERSION 2

#if defined(_WIN32)
#  if defined(PDC_WALLET_CORE_BUILD)
#    define PDC_WALLET_API __declspec(dllexport)
#  else
#    define PDC_WALLET_API __declspec(dllimport)
#  endif
#else
#  define PDC_WALLET_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Returns PDC_WALLET_CORE_ABI_VERSION; the binding refuses a library with a different value.
PDC_WALLET_API int32_t pdc_wallet_abi_version(void);

PDC_WALLET_API char* pdc_wallet_version(void);

// node_address: e.g. "https://node.example.org:19211". working_dir: where wallet files are kept.
PDC_WALLET_API char* pdc_wallet_init(const char* node_address, const char* working_dir, int32_t log_level);

PDC_WALLET_API char* pdc_wallet_generate(const char* path, const char* password);
PDC_WALLET_API char* pdc_wallet_restore(const char* seed, const char* path, const char* password, const char* seed_password);
PDC_WALLET_API char* pdc_wallet_open(const char* path, const char* password);
PDC_WALLET_API char* pdc_wallet_close(int64_t wallet_id);

PDC_WALLET_API char* pdc_wallet_status(int64_t wallet_id);

// json_rpc_request: a complete JSON-RPC 2.0 request for the wallet RPC server
// ({"jsonrpc":"2.0","id":0,"method":"getbalance","params":{}}).
PDC_WALLET_API char* pdc_wallet_invoke(int64_t wallet_id, const char* json_rpc_request);

// Stops the engine and joins its threads. Call it once before the process exits (and before unloading the library).
// The library cannot do this safely on its own at exit on Windows: its static destructor runs under the loader lock
// and waiting for threads there deadlocks, leaving a process that never ends. Afterwards pdc_wallet_init() may be
// called again. Open wallets are closed without being saved again: close them first if they must be stored.
PDC_WALLET_API char* pdc_wallet_shutdown(void);

// Releases a string returned by any function above. NULL is allowed.
PDC_WALLET_API void pdc_wallet_free(char* s);

#ifdef __cplusplus
}
#endif
