// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

// C ABI over plain_wallet_api for the remote-only wallet library; see pdc_wallet_core.h for the contract.
// Built only with -D BUILD_WALLET_CORE_LIB=ON (which also defines MOBILE_WALLET_BUILD: no local node, no p2p).

#define PDC_WALLET_CORE_BUILD
#include "pdc_wallet_core.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>

#include "wallet/plain_wallet_api.h"

namespace
{
  char* to_c_string(const std::string& s)
  {
    char* r = static_cast<char*>(std::malloc(s.size() + 1));
    if (!r)
      return nullptr;
    std::memcpy(r, s.c_str(), s.size() + 1);
    return r;
  }

  std::string json_escape(const char* text)
  {
    std::string out;
    for (const char* p = text ? text : ""; *p; ++p)
    {
      const unsigned char c = static_cast<unsigned char>(*p);
      switch (c)
      {
      case '"':  out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20)
        {
          static const char* hex = "0123456789abcdef";
          out += "\\u00";
          out += hex[c >> 4];
          out += hex[c & 0xf];
        }
        else
        {
          out += static_cast<char>(c);
        }
      }
    }
    return out;
  }

  std::string error_json(const char* message)
  {
    return std::string("{\"error\":{\"code\":\"INTERNAL_ERROR\",\"message\":\"") + json_escape(message) + "\"}}";
  }

  const char* safe(const char* s) { return s ? s : ""; }

  // No exception may cross the C boundary: the caller is Dart (or any other FFI host).
  template<class F>
  char* guarded(F call)
  {
    try
    {
      return to_c_string(call());
    }
    catch (const std::exception& e)
    {
      return to_c_string(error_json(e.what()));
    }
    catch (...)
    {
      return to_c_string(error_json("unknown error"));
    }
  }
}

extern "C"
{
  int32_t pdc_wallet_abi_version(void)
  {
    return PDC_WALLET_CORE_ABI_VERSION;
  }

  char* pdc_wallet_version(void)
  {
    return guarded([] { return plain_wallet::get_version(); });
  }

  char* pdc_wallet_init(const char* node_address, const char* working_dir, int32_t log_level)
  {
    return guarded([&] { return plain_wallet::init(safe(node_address), safe(working_dir), static_cast<int>(log_level)); });
  }

  char* pdc_wallet_generate(const char* path, const char* password)
  {
    return guarded([&] { return plain_wallet::generate(safe(path), safe(password)); });
  }

  char* pdc_wallet_restore(const char* seed, const char* path, const char* password, const char* seed_password)
  {
    return guarded([&] { return plain_wallet::restore(safe(seed), safe(path), safe(password), safe(seed_password)); });
  }

  char* pdc_wallet_open(const char* path, const char* password)
  {
    return guarded([&] { return plain_wallet::open(safe(path), safe(password)); });
  }

  char* pdc_wallet_close(int64_t wallet_id)
  {
    return guarded([&] { return plain_wallet::close_wallet(wallet_id); });
  }

  char* pdc_wallet_status(int64_t wallet_id)
  {
    return guarded([&] { return plain_wallet::get_wallet_status(wallet_id); });
  }

  char* pdc_wallet_invoke(int64_t wallet_id, const char* json_rpc_request)
  {
    return guarded([&] { return plain_wallet::invoke(wallet_id, safe(json_rpc_request)); });
  }

  void pdc_wallet_free(char* s)
  {
    std::free(s);
  }
}
