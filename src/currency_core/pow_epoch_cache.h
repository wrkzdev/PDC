// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <utility>
#include <vector>

// Ownership and eviction of RandomARQ per-epoch caches / datasets.
//
// NOTE: this is memory management only. It never changes which seed or flags
// are used to hash a block, so PoW results are bit-for-bit identical to the
// previous single-cache implementation (see basic_pow_helpers.cpp).
//
// Cache and dataset objects are reference counted. A VM that is still hashing
// on one thread keeps its epoch alive through shared_ptr, so another thread can
// move to the next epoch without leaking the old cache (the old code appended
// it to a list that was never freed) and without freeing it under the VM.
//
// Api requirements (see real_randomx_api in basic_pow_helpers.cpp):
//   typedefs : cache_t, dataset_t, seed_t, flags_t
//   statics  : cache_t*   alloc_cache(flags_t)
//              void       init_cache(cache_t*, const seed_t&)
//              void       release_cache(cache_t*)
//              dataset_t* alloc_dataset(flags_t)
//              void       init_dataset(dataset_t*, cache_t*)
//              void       release_dataset(dataset_t*)
//              bool       has_jit(flags_t)
//              flags_t    without_jit(flags_t)
//
// Not thread safe on its own: callers serialize access with a mutex.

namespace currency
{
  template<typename Api>
  class pow_epoch_cache
  {
  public:
    typedef typename Api::cache_t   cache_t;
    typedef typename Api::dataset_t dataset_t;
    typedef typename Api::seed_t    seed_t;
    typedef typename Api::flags_t   flags_t;

    // number of epochs kept resident: the current one and the previous one,
    // so a reorg or an alt block straddling an epoch boundary doesn't thrash
    static const size_t max_resident_epochs = 2;

    struct handle
    {
      int epoch = -1;
      std::shared_ptr<cache_t> cache;
      std::shared_ptr<dataset_t> dataset; // null in light mode

      bool operator==(const handle& r) const { return epoch == r.epoch && cache == r.cache && dataset == r.dataset; }
      bool operator!=(const handle& r) const { return !(*this == r); }
    };

    explicit pow_epoch_cache(flags_t flags) : m_flags(flags) {}

    flags_t flags() const { return m_flags; }
    size_t resident_epochs() const { return m_entries.size(); }

    // Returns the cache for the epoch, creating it (and evicting the least
    // recently used one) when needed. With want_dataset the newest epoch also
    // gets a full dataset; datasets of older epochs are always dropped.
    // Throws std::runtime_error if the cache cannot be allocated.
    handle acquire(int epoch, const seed_t& seed, bool want_dataset)
    {
      entry* e = find(epoch);
      if (!e)
        e = &insert(epoch, seed);
      else
        touch(e);

      if (want_dataset && is_newest(epoch))
      {
        drop_datasets_except(epoch);
        if (!e->dataset)
          e->dataset = make_dataset(e->cache);
      }
      else
      {
        e->dataset.reset();
      }
      return make_handle(*e);
    }

    // Drop every full dataset (leaving light caches). Datasets are freed as soon
    // as the last VM using them lets go.
    void drop_all_datasets()
    {
      for (entry& e : m_entries)
        e.dataset.reset();
    }

    // Used when a JIT-enabled VM could not be created: forget all caches and
    // continue without JIT. Existing VMs keep their own (old) objects alive.
    void reset_without_jit()
    {
      m_entries.clear();
      m_flags = Api::without_jit(m_flags);
    }

  private:
    struct entry
    {
      int epoch = -1;
      uint64_t last_use = 0;
      std::shared_ptr<cache_t> cache;
      std::shared_ptr<dataset_t> dataset;
    };

    static handle make_handle(const entry& e)
    {
      handle h;
      h.epoch = e.epoch;
      h.cache = e.cache;
      h.dataset = e.dataset;
      return h;
    }

    entry* find(int epoch)
    {
      for (entry& e : m_entries)
        if (e.epoch == epoch)
          return &e;
      return nullptr;
    }

    void touch(entry* e) { e->last_use = ++m_clock; }

    bool is_newest(int epoch) const
    {
      for (const entry& e : m_entries)
        if (e.epoch > epoch)
          return false;
      return true;
    }

    void drop_datasets_except(int epoch)
    {
      for (entry& e : m_entries)
        if (e.epoch != epoch)
          e.dataset.reset();
    }

    entry& insert(int epoch, const seed_t& seed)
    {
      std::shared_ptr<cache_t> cache = make_cache(seed);

      if (m_entries.size() >= max_resident_epochs)
      {
        size_t victim = 0;
        for (size_t i = 1; i < m_entries.size(); ++i)
          if (m_entries[i].last_use < m_entries[victim].last_use)
            victim = i;
        m_entries.erase(m_entries.begin() + victim);
      }

      m_entries.emplace_back();
      entry& e = m_entries.back();
      e.epoch = epoch;
      e.cache = std::move(cache);
      touch(&e);
      return e;
    }

    std::shared_ptr<cache_t> make_cache(const seed_t& seed)
    {
      cache_t* raw = Api::alloc_cache(m_flags);
      if (!raw && Api::has_jit(m_flags))
      {
        m_flags = Api::without_jit(m_flags);
        raw = Api::alloc_cache(m_flags);
      }
      if (!raw)
        throw std::runtime_error("RandomARQ: failed to allocate cache");
      std::shared_ptr<cache_t> p(raw, [](cache_t* c) { Api::release_cache(c); });
      Api::init_cache(raw, seed);
      return p;
    }

    std::shared_ptr<dataset_t> make_dataset(const std::shared_ptr<cache_t>& cache)
    {
      dataset_t* raw = Api::alloc_dataset(m_flags);
      if (!raw)
        return std::shared_ptr<dataset_t>(); // stay in light mode
      std::shared_ptr<dataset_t> p(raw, [](dataset_t* d) { Api::release_dataset(d); });
      Api::init_dataset(raw, cache.get());
      return p;
    }

    flags_t m_flags;
    uint64_t m_clock = 0;
    std::vector<entry> m_entries;
  };
}
