// Copyright (c) 2018-2019 Zano Project
// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.


#include "include_base_utils.h"
using namespace epee;

#include "basic_pow_helpers.h"
#include "currency_format_utils.h"
#include "serialization/binary_utils.h"
#include "serialization/stl_containers.h"
#include "currency_core/currency_config.h"
#include "crypto/crypto.h"
#include "crypto/hash.h"
#include "common/int-util.h"
#include "pow_epoch_cache.h"

#include <cstring>
#include <mutex>
#include <vector>
#include <randomx.h>

namespace currency
{
  namespace
  {
    // Thin adapter over the RandomARQ C API, see pow_epoch_cache.h
    struct real_randomx_api
    {
      typedef randomx_cache cache_t;
      typedef randomx_dataset dataset_t;
      typedef crypto::hash seed_t;
      typedef randomx_flags flags_t;

      static randomx_cache* alloc_cache(randomx_flags flags)
      {
        randomx_cache* c = randomx_alloc_cache(flags);
        if (!c && (flags & RANDOMX_FLAG_JIT))
          LOG_PRINT_YELLOW("RandomARQ: JIT cache alloc failed, falling back to interpreter", LOG_LEVEL_0);
        return c;
      }
      static void init_cache(randomx_cache* c, const crypto::hash& seed)
      {
        randomx_init_cache(c, &seed, sizeof(seed));
        LOG_PRINT_L0("RandomARQ: epoch cache initialized, seed " << seed);
      }
      static void release_cache(randomx_cache* c)
      {
        randomx_release_cache(c);
        LOG_PRINT_L0("RandomARQ: epoch cache released");
      }
      static randomx_dataset* alloc_dataset(randomx_flags flags)
      {
        LOG_PRINT_YELLOW("RandomARQ: allocating full dataset for CPU mining (approx. 2 GiB)...", LOG_LEVEL_0);
        randomx_dataset* d = randomx_alloc_dataset(flags);
        if (!d)
          LOG_PRINT_RED("RandomARQ: dataset allocation failed, staying on light mode", LOG_LEVEL_0);
        return d;
      }
      static void init_dataset(randomx_dataset* d, randomx_cache* c)
      {
        randomx_init_dataset(d, c, 0, randomx_dataset_item_count());
        LOG_PRINT_GREEN("RandomARQ: full dataset ready", LOG_LEVEL_0);
      }
      static void release_dataset(randomx_dataset* d)
      {
        randomx_release_dataset(d);
        LOG_PRINT_L0("RandomARQ: full dataset released");
      }
      static bool has_jit(randomx_flags flags)
      {
        return (flags & RANDOMX_FLAG_JIT) != 0;
      }
      static randomx_flags without_jit(randomx_flags flags)
      {
        return static_cast<randomx_flags>(flags & ~(RANDOMX_FLAG_JIT | RANDOMX_FLAG_SECURE));
      }
    };

    typedef pow_epoch_cache<real_randomx_api> rx_epoch_cache_t;

    std::mutex g_rx_mutex;
    bool g_rx_mining_mode = false;
    bool g_rx_self_checked = false;

    randomx_flags select_rx_flags()
    {
      randomx_flags flags = randomx_get_flags();
#if defined(__APPLE__) && defined(__aarch64__)
      // RandomARQ's A64 JIT emits into RWX pages without MAP_JIT. On Apple
      // Silicon that leaves a null/non-executable code buffer: the same block
      // hashes to two different PoW values, then JitCompilerA64 SIGSEGVs.
      flags = real_randomx_api::without_jit(flags);
#endif
      return flags;
    }

    // must be called with g_rx_mutex held
    rx_epoch_cache_t& rx_cache_locked()
    {
      // intentionally never destroyed: releasing caches from a static destructor
      // would log after the logger is gone, and the OS reclaims it at exit anyway
      static rx_epoch_cache_t* cache = new rx_epoch_cache_t(select_rx_flags());
      return *cache;
    }

    // Per-thread VM. It co-owns the cache/dataset it was built on, so an epoch
    // switch on another thread can't free them under a running hash, and they
    // are released as soon as the last VM using them is replaced or the thread ends.
    struct tls_vm_state
    {
      randomx_vm* vm = nullptr;
      rx_epoch_cache_t::handle h;

      void reset()
      {
        if (vm)
        {
          randomx_destroy_vm(vm);
          vm = nullptr;
        }
        h = rx_epoch_cache_t::handle();
      }
      ~tls_vm_state() { reset(); }
    };
    thread_local tls_vm_state tls_rx;

    void self_check_vm_locked(randomx_vm* vm)
    {
      if (g_rx_self_checked || !vm)
        return;
      crypto::hash first = null_hash;
      crypto::hash second = null_hash;
      uint8_t probe[POW_BLOB_SIZE] = {};
      randomx_calculate_hash(vm, probe, sizeof(probe), &first);
      randomx_calculate_hash(vm, probe, sizeof(probe), &second);
      CHECK_AND_ASSERT_THROW_MES(first == second, "RandomARQ is non-deterministic on this CPU; refusing to verify blocks");
      g_rx_self_checked = true;
      LOG_PRINT_GREEN("RandomARQ self-check OK (flags=" << static_cast<unsigned>(rx_cache_locked().flags()) << ")", LOG_LEVEL_0);
    }

    randomx_vm* create_vm_locked(const rx_epoch_cache_t::handle& h)
    {
      const bool want_full = h.dataset != nullptr;
      randomx_flags vm_flags = rx_cache_locked().flags();
      if (want_full)
        vm_flags = static_cast<randomx_flags>(vm_flags | RANDOMX_FLAG_FULL_MEM);
      return randomx_create_vm(vm_flags, want_full ? nullptr : h.cache.get(), h.dataset.get());
    }

    randomx_vm* ensure_vm_locked(int epoch, const crypto::hash& seed)
    {
      rx_epoch_cache_t& caches = rx_cache_locked();
      rx_epoch_cache_t::handle h = caches.acquire(epoch, seed, g_rx_mining_mode);
      if (tls_rx.vm && tls_rx.h == h)
        return tls_rx.vm;

      tls_rx.reset();
      randomx_vm* vm = create_vm_locked(h);
      if (!vm && real_randomx_api::has_jit(caches.flags()))
      {
        LOG_PRINT_YELLOW("RandomARQ: JIT VM failed, recreating cache without JIT", LOG_LEVEL_0);
        caches.reset_without_jit();
        h = caches.acquire(epoch, seed, g_rx_mining_mode);
        vm = create_vm_locked(h);
      }
      CHECK_AND_ASSERT_THROW_MES(vm, "RandomARQ: failed to create VM");
      tls_rx.vm = vm;
      tls_rx.h = h;
      self_check_vm_locked(vm);
      return vm;
    }
  }

  int pow_height_to_epoch(uint64_t height)
  {
    return static_cast<int>(height / RANDOMX_EPOCH_LENGTH);
  }

  crypto::hash pow_epoch_to_seed(int epoch)
  {
    uint8_t buf[20] = {};
    memcpy(buf, "PDC-RandomARQ", 13);
    const uint32_t epoch_le = static_cast<uint32_t>(epoch);
    memcpy(buf + 16, &epoch_le, sizeof(epoch_le));
    return crypto::cn_fast_hash(buf, sizeof(buf));
  }

  void fill_pow_blob(uint8_t blob[POW_BLOB_SIZE], const crypto::hash& block_header_hash, uint64_t nonce)
  {
    static_assert(POW_BLOB_SIZE == 43, "XMRig rx/arq hashing blob is 43 bytes");
    static_assert(POW_NONCE_OFFSET + sizeof(uint32_t) == POW_BLOB_SIZE, "XMRig nonce is 4 LE bytes at offset 39");
    memset(blob, 0, POW_BLOB_SIZE);
    memcpy(blob, &block_header_hash, sizeof(block_header_hash));
    // RandomARQ / XMRig only search a 32-bit nonce space; ignore high bits.
    const uint32_t nonce32 = static_cast<uint32_t>(nonce & 0xffffffffull);
    memcpy(blob + POW_NONCE_OFFSET, &nonce32, sizeof(nonce32));
  }

  void randomx_set_mining_mode(bool enable_full_dataset)
  {
    std::lock_guard<std::mutex> lock(g_rx_mutex);
    g_rx_mining_mode = enable_full_dataset;
    if (!enable_full_dataset)
    {
      rx_cache_locked().drop_all_datasets();
      tls_rx.reset();
    }
  }

  crypto::hash get_block_longhash(uint64_t height, const crypto::hash& block_header_hash, uint64_t nonce)
  {
    const int epoch = pow_height_to_epoch(height);
    const crypto::hash seed = pow_epoch_to_seed(epoch);

    uint8_t input[POW_BLOB_SIZE] = {};
    fill_pow_blob(input, block_header_hash, nonce);

    randomx_vm* vm = nullptr;
    {
      std::lock_guard<std::mutex> lock(g_rx_mutex);
      vm = ensure_vm_locked(epoch, seed);
    }
    crypto::hash result = null_hash;
    randomx_calculate_hash(vm, input, sizeof(input), &result);
    return result;
  }

  crypto::hash get_block_header_mining_hash(const block& b)
  {
    blobdata bd = get_block_hashing_blob(b);

    set_nonce_in_block_blob(bd, 0);
    return crypto::cn_fast_hash(bd.data(), bd.size());
  }

  void get_block_longhash(const block& b, crypto::hash& res)
  {
    /*
    RandomARQ is keyed by epoch seed and hashes a 43-byte blob matching XMRig rx/arq:
    header_hash (32) || padding (7) || nonce_le32 at offset 39.
    Header hash is computed from the block blob with nonce zeroed.
    Proof-of-stake is unchanged and does not use this function.
    */
    crypto::hash bl_hash = get_block_header_mining_hash(b);
    // Bind block ID to the same 32-bit nonce space XMRig searches.
    res = get_block_longhash(get_block_height(b), bl_hash, b.nonce & 0xffffffffull);
  }

  crypto::hash get_block_longhash(const block& b)
  {
    crypto::hash p = null_hash;
    get_block_longhash(b, p);
    return p;
  }
}
