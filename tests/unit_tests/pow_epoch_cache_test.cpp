// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "gtest/gtest.h"

#include <cstdint>
#include <stdexcept>

#include "currency_core/pow_epoch_cache.h"

namespace
{
  // Fake RandomX API that counts live objects, so leaks are directly observable.
  struct fake_api
  {
    struct cache_t { int seed; };
    struct dataset_t { int seed; };
    typedef int seed_t;
    typedef unsigned flags_t;

    static const flags_t JIT = 1;

    static int live_caches;
    static int live_datasets;
    static int total_caches_created;
    static bool fail_jit_cache_alloc;
    static bool fail_all_cache_alloc;
    static bool fail_dataset_alloc;

    static void reset()
    {
      live_caches = live_datasets = total_caches_created = 0;
      fail_jit_cache_alloc = fail_all_cache_alloc = fail_dataset_alloc = false;
    }

    static cache_t* alloc_cache(flags_t flags)
    {
      if (fail_all_cache_alloc || (fail_jit_cache_alloc && (flags & JIT)))
        return nullptr;
      ++live_caches;
      ++total_caches_created;
      return new cache_t{0};
    }
    static void init_cache(cache_t* c, const seed_t& seed) { c->seed = seed; }
    static void release_cache(cache_t* c) { --live_caches; delete c; }
    static dataset_t* alloc_dataset(flags_t)
    {
      if (fail_dataset_alloc)
        return nullptr;
      ++live_datasets;
      return new dataset_t{0};
    }
    static void init_dataset(dataset_t* d, cache_t* c) { d->seed = c->seed; }
    static void release_dataset(dataset_t* d) { --live_datasets; delete d; }
    static bool has_jit(flags_t f) { return (f & JIT) != 0; }
    static flags_t without_jit(flags_t f) { return f & ~JIT; }
  };

  int fake_api::live_caches = 0;
  int fake_api::live_datasets = 0;
  int fake_api::total_caches_created = 0;
  bool fake_api::fail_jit_cache_alloc = false;
  bool fake_api::fail_all_cache_alloc = false;
  bool fake_api::fail_dataset_alloc = false;

  typedef currency::pow_epoch_cache<fake_api> cache_set_t;

  struct pow_epoch_cache_fixture : public ::testing::Test
  {
    void SetUp() override { fake_api::reset(); }
    void TearDown() override { EXPECT_EQ(0, fake_api::live_caches); EXPECT_EQ(0, fake_api::live_datasets); }
  };
}

// Before the fix every epoch change leaked the previous cache: after N epochs, N caches stayed alive.
TEST_F(pow_epoch_cache_fixture, memory_is_bounded_across_many_epochs)
{
  {
    cache_set_t set(0);
    for (int epoch = 0; epoch < 500; ++epoch)
    {
      cache_set_t::handle h = set.acquire(epoch, epoch, false);
      ASSERT_TRUE(h.cache != nullptr);
      ASSERT_EQ(epoch, h.cache->seed);
      ASSERT_LE(fake_api::live_caches, (int)cache_set_t::max_resident_epochs);
    }
    ASSERT_EQ((int)cache_set_t::max_resident_epochs, fake_api::live_caches);
  }
  // set destroyed, every handle dropped
  ASSERT_EQ(0, fake_api::live_caches);
}

TEST_F(pow_epoch_cache_fixture, same_epoch_is_reused)
{
  cache_set_t set(0);
  cache_set_t::handle a = set.acquire(7, 7, false);
  cache_set_t::handle b = set.acquire(7, 7, false);
  ASSERT_TRUE(a == b);
  ASSERT_EQ(1, fake_api::total_caches_created);
}

// A reorg / alt block straddling an epoch boundary alternates between two epochs. That must not rebuild a cache each time.
TEST_F(pow_epoch_cache_fixture, epoch_boundary_flip_flop_does_not_thrash)
{
  cache_set_t set(0);
  for (int i = 0; i < 50; ++i)
  {
    set.acquire(0, 0, false);
    set.acquire(1, 1, false);
  }
  ASSERT_EQ(2, fake_api::total_caches_created);
  ASSERT_EQ(2, fake_api::live_caches);
}

// A VM that is still hashing on another thread holds a handle: the cache it uses must survive eviction, then be freed.
TEST_F(pow_epoch_cache_fixture, handle_in_use_survives_eviction_and_is_freed_after)
{
  cache_set_t set(0);
  cache_set_t::handle in_use = set.acquire(0, 100, false);
  set.acquire(1, 101, false);
  set.acquire(2, 102, false); // evicts epoch 0 from the set
  ASSERT_EQ(2, (int)set.resident_epochs());
  ASSERT_EQ(3, fake_api::live_caches); // epoch 0 still owned by in_use
  ASSERT_EQ(100, in_use.cache->seed);  // and still valid

  in_use = cache_set_t::handle();
  ASSERT_EQ(2, fake_api::live_caches);
}

TEST_F(pow_epoch_cache_fixture, dataset_only_for_newest_epoch)
{
  cache_set_t set(0);
  cache_set_t::handle e0 = set.acquire(0, 0, true);
  ASSERT_TRUE(e0.dataset != nullptr);
  ASSERT_EQ(1, fake_api::live_datasets);

  cache_set_t::handle e1 = set.acquire(1, 1, true);
  ASSERT_TRUE(e1.dataset != nullptr);
  // epoch 0 lost its dataset in the set, but our handle still keeps it alive
  ASSERT_EQ(2, fake_api::live_datasets);
  e0 = cache_set_t::handle();
  ASSERT_EQ(1, fake_api::live_datasets);

  // an older epoch requested again (alt chain) gets a light cache only and doesn't disturb the newest dataset
  cache_set_t::handle old0 = set.acquire(0, 0, true);
  ASSERT_TRUE(old0.dataset == nullptr);
  cache_set_t::handle e1_again = set.acquire(1, 1, true);
  ASSERT_TRUE(e1_again.dataset == e1.dataset);
  ASSERT_EQ(1, fake_api::live_datasets);
}

TEST_F(pow_epoch_cache_fixture, leaving_mining_mode_frees_dataset)
{
  cache_set_t set(0);
  set.acquire(3, 3, true);
  ASSERT_EQ(1, fake_api::live_datasets);
  set.drop_all_datasets();
  ASSERT_EQ(0, fake_api::live_datasets);
  cache_set_t::handle light = set.acquire(3, 3, false);
  ASSERT_TRUE(light.dataset == nullptr);
}

TEST_F(pow_epoch_cache_fixture, dataset_alloc_failure_falls_back_to_light)
{
  cache_set_t set(0);
  fake_api::fail_dataset_alloc = true;
  cache_set_t::handle h = set.acquire(0, 0, true);
  ASSERT_TRUE(h.cache != nullptr);
  ASSERT_TRUE(h.dataset == nullptr);
}

TEST_F(pow_epoch_cache_fixture, jit_cache_alloc_failure_falls_back_to_interpreter)
{
  cache_set_t set(fake_api::JIT);
  fake_api::fail_jit_cache_alloc = true;
  cache_set_t::handle h = set.acquire(0, 0, false);
  ASSERT_TRUE(h.cache != nullptr);
  ASSERT_EQ(0u, set.flags() & fake_api::JIT);
}

TEST_F(pow_epoch_cache_fixture, reset_without_jit_keeps_old_handles_valid)
{
  cache_set_t set(fake_api::JIT);
  cache_set_t::handle old = set.acquire(5, 55, false);
  set.reset_without_jit();
  ASSERT_EQ(0u, set.flags() & fake_api::JIT);
  ASSERT_EQ(0, (int)set.resident_epochs());
  ASSERT_EQ(55, old.cache->seed);
  ASSERT_EQ(1, fake_api::live_caches);
}

TEST_F(pow_epoch_cache_fixture, hard_alloc_failure_throws_and_leaves_set_usable)
{
  cache_set_t set(0);
  set.acquire(0, 0, false);
  fake_api::fail_all_cache_alloc = true;
  ASSERT_THROW(set.acquire(1, 1, false), std::runtime_error);
  ASSERT_EQ(1, (int)set.resident_epochs());   // failed insert evicted nothing
  fake_api::fail_all_cache_alloc = false;
  ASSERT_NO_THROW(set.acquire(1, 1, false));
}
