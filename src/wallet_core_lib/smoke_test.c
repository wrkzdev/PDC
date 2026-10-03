/* Smoke test for the real pdc_wallet_core library (run by the walletlib Docker stage).
 *   smoke_test <path to libpdc_wallet_core.so> <working dir>
 * Loads the library through dlopen like an FFI host does, creates a wallet offline (the node address points nowhere),
 * and checks that the real engine answers the calls the Flutter wallet makes with the shapes it expects. */

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int32_t (*abi_fn)(void);
typedef char* (*str0_fn)(void);
typedef char* (*init_fn)(const char*, const char*, int32_t);
typedef char* (*str2_fn)(const char*, const char*);
typedef char* (*id_fn)(int64_t);
typedef char* (*invoke_fn)(int64_t, const char*);
typedef void (*free_fn)(char*);

static int failures = 0;

static void check(int ok, const char* what, const char* detail)
{
    printf("%s %s%s%s\n", ok ? "ok  " : "FAIL", what, detail ? ": " : "", detail ? detail : "");
    if (!ok) failures++;
}

static void* sym(void* lib, const char* name)
{
    void* p = dlsym(lib, name);
    if (!p) { printf("FAIL missing symbol %s\n", name); exit(2); }
    return p;
}

static int64_t wallet_id_of(const char* json)
{
    const char* k = strstr(json, "\"wallet_id\"");
    if (!k) return -1;
    k = strchr(k, ':');
    return k ? (int64_t)strtoll(k + 1, NULL, 10) : -1;
}

int main(int argc, char** argv)
{
    if (argc < 3) { fprintf(stderr, "usage: %s lib workdir\n", argv[0]); return 2; }
    void* lib = dlopen(argv[1], RTLD_NOW);
    if (!lib) { printf("FAIL dlopen: %s\n", dlerror()); return 2; }

    abi_fn abi = (abi_fn)sym(lib, "pdc_wallet_abi_version");
    str0_fn version = (str0_fn)sym(lib, "pdc_wallet_version");
    init_fn init = (init_fn)sym(lib, "pdc_wallet_init");
    str2_fn generate = (str2_fn)sym(lib, "pdc_wallet_generate");
    id_fn close_w = (id_fn)sym(lib, "pdc_wallet_close");
    id_fn status = (id_fn)sym(lib, "pdc_wallet_status");
    invoke_fn invoke = (invoke_fn)sym(lib, "pdc_wallet_invoke");
    free_fn release = (free_fn)sym(lib, "pdc_wallet_free");

    check(abi() == 1, "abi version is 1", NULL);

    char* v = version();
    check(v && v[0], "version string", v);
    release(v);

    release(NULL); /* must be allowed */

    char* r = init("http://127.0.0.1:1", argv[2], 0);
    check(r != NULL, "init returns a string", r);
    release(r);

    r = generate("smoke.wallet", "smoke-password-1");
    check(r && strstr(r, "\"wallet_id\"") && strstr(r, "\"seed\""), "generate returns a wallet id and a seed", r ? "(reply received)" : NULL);
    int64_t id = r ? wallet_id_of(r) : -1;
    if (r) {
        /* never print the seed: count its words only */
        const char* s = strstr(r, "\"seed\"");
        int words = 0;
        if (s) {
            s = strchr(s + 6, '"');
            if (s) {
                const char* e = strchr(s + 1, '"');
                for (const char* p = s + 1; e && p < e; p++)
                    if (*p != ' ' && (p == s + 1 || p[-1] == ' ')) words++;
            }
        }
        char buf[32];
        snprintf(buf, sizeof buf, "%d words", words);
        check(words >= 24 && words <= 26, "recovery phrase has 24-26 words", buf);
    }
    release(r);

    if (id >= 0) {
        r = invoke(id, "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"getaddress\",\"params\":{}}");
        check(r && strstr(r, "\"address\"") && strstr(r, "\"Px"), "getaddress returns a Px address", r);
        release(r);

        r = invoke(id, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getbalance\",\"params\":{}}");
        check(r && strstr(r, "\"balances\"") && strstr(r, "\"unlocked_balance\""), "getbalance has balances and unlocked_balance", r);
        release(r);

        r = status(id);
        check(r && strstr(r, "current_wallet_height"), "wallet status has heights", r);
        release(r);

        r = invoke(id, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"no_such_method\",\"params\":{}}");
        check(r != NULL, "unknown method answers instead of crashing", r);
        release(r);

        r = close_w(id);
        check(r != NULL, "close answers", r);
        release(r);
    }

    r = invoke(987654321, "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"getaddress\",\"params\":{}}");
    check(r && strstr(r, "WRONG_ID"), "invoking a wallet that does not exist is an error, not a crash", r);
    release(r);

    r = invoke(0, NULL);
    check(r != NULL, "NULL request is tolerated", r);
    release(r);

    printf(failures ? "SMOKE TEST FAILED (%d)\n" : "SMOKE TEST PASSED\n", failures);
    return failures ? 1 : 0;
}
