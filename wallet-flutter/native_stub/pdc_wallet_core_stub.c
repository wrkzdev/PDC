/* Stand-in for the real pdc_wallet_core library, implementing the same C ABI (src/wallet_core_lib/pdc_wallet_core.h) with
 * canned answers. It lets the Dart FFI binding be tested on any machine without building the C++ wallet.
 * It echoes what it received so the test can check string marshalling, handles, and that results are freed. */

#define PDC_WALLET_CORE_BUILD
#include "../../src/wallet_core_lib/pdc_wallet_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char* dup_str(const char* s)
{
    size_t n = strlen(s);
    char* r = (char*)malloc(n + 1);
    if (r) memcpy(r, s, n + 1);
    return r;
}

/* Builds {"echo":"<what>"} without escaping: the test only sends characters that need none. */
static char* echo_json(const char* what, const char* a, const char* b)
{
    const char* sa = a ? a : "";
    const char* sb = b ? b : "";
    size_t n = strlen(what) + strlen(sa) + strlen(sb) + 64;
    char* r = (char*)malloc(n);
    if (r) snprintf(r, n, "{\"echo\":\"%s\",\"a\":\"%s\",\"b\":\"%s\"}", what, sa, sb);
    return r;
}

/* -DSTUB_ABI_VERSION=999 builds a deliberately incompatible library for the mismatch test */
#ifndef STUB_ABI_VERSION
#define STUB_ABI_VERSION PDC_WALLET_CORE_ABI_VERSION
#endif
int32_t pdc_wallet_abi_version(void) { return STUB_ABI_VERSION; }

char* pdc_wallet_version(void) { return dup_str("stub-1.0"); }

char* pdc_wallet_init(const char* node_address, const char* working_dir, int32_t log_level)
{
    (void)log_level;
    if (node_address && strcmp(node_address, "fail") == 0) return dup_str("{\"id\":0,\"jsonrpc\":\"\",\"result\":{\"return_code\":\"BAD_ARG\"}}");
    (void)working_dir;
    return dup_str("{\"id\":0,\"jsonrpc\":\"\",\"result\":{\"return_code\":\"OK\"}}");
}

char* pdc_wallet_generate(const char* path, const char* password)
{
    (void)password;
    char* r = (char*)malloc(strlen(path ? path : "") + 128);
    if (r) sprintf(r, "{\"id\":0,\"jsonrpc\":\"2.0\",\"result\":{\"wallet_id\":7,\"seed\":\"word1 word2\",\"name\":\"%s\"}}", path ? path : "");
    return r;
}

char* pdc_wallet_restore(const char* seed, const char* path, const char* password, const char* seed_password)
{
    (void)password;
    (void)seed_password;
    return echo_json("restore", seed, path);
}

char* pdc_wallet_open(const char* path, const char* password)
{
    if (password && strcmp(password, "wrong") == 0) return dup_str("{\"error\":{\"code\":\"WRONG_PASSWORD\"}}");
    (void)path;
    return dup_str("{\"id\":0,\"jsonrpc\":\"2.0\",\"result\":{\"wallet_id\":9}}");
}

char* pdc_wallet_close(int64_t wallet_id)
{
    char buf[64];
    snprintf(buf, sizeof buf, "closed %lld", (long long)wallet_id);
    return dup_str(buf);
}

char* pdc_wallet_status(int64_t wallet_id)
{
    (void)wallet_id;
    return dup_str("{\"current_wallet_height\":50,\"current_daemon_height\":200}");
}

char* pdc_wallet_invoke(int64_t wallet_id, const char* json_rpc_request)
{
    const char* req = json_rpc_request ? json_rpc_request : "";
    char head[48];
    snprintf(head, sizeof head, "{\"wallet\":%lld,\"len\":%zu,\"request\":", (long long)wallet_id, strlen(req));
    size_t n = strlen(head) + strlen(req) + 8;
    char* r = (char*)malloc(n);
    if (!r) return NULL;
    /* request is itself JSON, so it can be embedded verbatim */
    snprintf(r, n, "%s%s}", head, req);
    return r;
}

char* pdc_wallet_shutdown(void) { return dup_str("{\"response\": \"OK\"}"); }

void pdc_wallet_free(char* s) { free(s); }
