// Copyright (c) 2012-2013 The Cryptonote developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <exception>

#include "gtest/gtest.h"

#include "include_base_utils.h"
#include "currency_core/account.h"
#include "currency_core/currency_format_utils.h"

TEST(wallet_seed, store_restore_test) 
{
  for (size_t i = 0; i != 100; i++)
  {
    currency::account_base acc;
    acc.generate();
    auto seed_phrase = acc.get_seed_phrase("");
    
    currency::account_base acc2;
    bool r = acc2.restore_from_seed_phrase(seed_phrase, "");
    ASSERT_TRUE(r);

    if (memcmp(&acc2.get_keys(), &acc.get_keys(), sizeof(currency::account_keys)))
    {
      ASSERT_TRUE(false);
    }
  }

  for (size_t i = 0; i != 100; i++)
  {
    currency::account_base acc;
    acc.generate();
    auto seed_phrase = acc.get_seed_phrase("");

    currency::account_base acc2;
    bool r = acc2.restore_from_seed_phrase(seed_phrase, "");
    ASSERT_TRUE(r);

    if (memcmp(&acc2.get_keys(), &acc.get_keys(), sizeof(currency::account_keys)))
    {
      ASSERT_TRUE(false);
    }
  }

}

TEST(wallet_seed, restore_from_keys)
{
  // keys of known seed phrases (see wallet_seed_entries below): restoring from the keys gives the same account
  struct { const char* seed; const char* spend; const char* view; } vectors[] = {
    { "dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew god",
      "5e051454d7226b5734ebd64f754b57db4c655ecda00bd324f1b241d0b6381c0f", "7dde5590fdf430568c00556ac2accf09da6cde9a29a4bc7d1cb6fd267130f006" },
    { "conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation",
      "71162f207499bc16260957c36a6586bb931d54be33ff56b94d565dfedbb3c70e", "8454372096986c457f4e7dceef2f39b6050c35d87b31d9c9eb8d37bf8f1f430f" },
  };
  for (const auto& v : vectors)
  {
    currency::account_base from_seed;
    ASSERT_TRUE(from_seed.restore_from_seed_phrase(v.seed, ""));

    currency::account_base from_keys;
    ASSERT_TRUE(from_keys.restore_from_keys(std::string("keys:") + v.spend + ":" + v.view));
    ASSERT_EQ(0, memcmp(&from_keys.get_keys(), &from_seed.get_keys(), sizeof(currency::account_keys)));
    ASSERT_EQ(from_seed.get_public_address_str(), from_keys.get_public_address_str());
    ASSERT_FALSE(from_keys.is_auditable());
    ASSERT_FALSE(from_keys.is_watch_only());
    ASSERT_EQ("", from_keys.get_seed_phrase(""));

    // with a creation time
    currency::account_base dated;
    ASSERT_TRUE(dated.restore_from_keys(std::string("keys:") + v.spend + ":" + v.view + ":1700000000"));
    ASSERT_EQ(1700000000u, dated.get_createtime());
    ASSERT_EQ(from_seed.get_public_address_str(), dated.get_public_address_str());
  }

  // a randomly generated account round-trips through its own keys
  for (size_t i = 0; i != 20; i++)
  {
    currency::account_base acc;
    acc.generate();
    currency::account_base acc2;
    ASSERT_TRUE(acc2.restore_from_keys("keys:" + epee::string_tools::pod_to_hex(acc.get_keys().spend_secret_key) + ":" + epee::string_tools::pod_to_hex(acc.get_keys().view_secret_key)));
    ASSERT_EQ(acc.get_public_address_str(), acc2.get_public_address_str());
  }
}

TEST(wallet_seed, restore_from_keys_rejects_bad_input)
{
  const std::string spend = "5e051454d7226b5734ebd64f754b57db4c655ecda00bd324f1b241d0b6381c0f";
  const std::string view = "7dde5590fdf430568c00556ac2accf09da6cde9a29a4bc7d1cb6fd267130f006";
  const std::string other_view = "8454372096986c457f4e7dceef2f39b6050c35d87b31d9c9eb8d37bf8f1f430f";
  const std::string zeros(64, '0');
  const std::string ff(64, 'f'); // not a canonical scalar

  const std::string bad[] = {
    "",
    "keys:",
    "keys:" + spend,                                  // view key missing
    "keys:" + spend + ":" + other_view,               // view key of another wallet
    "keys:" + view + ":" + spend,                     // swapped
    "keys:" + zeros + ":" + zeros,                    // null keys
    "keys:" + ff + ":" + ff,                          // out of range
    "keys:" + spend.substr(1) + ":" + view,           // too short
    "keys:" + spend + "00:" + view,                   // too long
    "keys:" + spend + ":" + view.substr(0, 63) + "g", // not hex
    "keys:" + spend + ":" + view + ":123",            // creation time before the wallet epoch
    "keys:" + spend + ":" + view + ":abc",
    "keys:" + spend + ":" + view + ":1700000000:1",
    "KEYS:" + spend + ":" + view,                     // the prefix is case sensitive
    spend + ":" + view,                               // without the prefix this is a (rejected) tracking seed
  };
  for (const auto& s : bad)
  {
    currency::account_base acc;
    ASSERT_FALSE(acc.restore_from_keys(s)) << s;
  }

  ASSERT_TRUE(currency::account_base::is_keys_restore_string("keys:abc"));
  ASSERT_FALSE(currency::account_base::is_keys_restore_string("Px123:abc"));
  ASSERT_FALSE(currency::account_base::is_seed_tracking("keys:" + spend + ":" + view));
  ASSERT_TRUE(currency::account_base::is_seed_tracking("Px123:abc"));
}

struct wallet_seed_entry
{
  std::string seed_phrase;
  std::string spend_secret_key;
  std::string view_secret_key;
  uint64_t timestamp;
  bool auditable;
  bool valid;
};

wallet_seed_entry wallet_seed_entries[] = 
{
  {
    // legacy 24-word seed phrase -- invalid
    "dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew god",
    "",
    "",
    0,
    false,
    false
  },
  {
    // old-style 25-word seed phrase -- valid
    "dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew god",
    "5e051454d7226b5734ebd64f754b57db4c655ecda00bd324f1b241d0b6381c0f",
    "7dde5590fdf430568c00556ac2accf09da6cde9a29a4bc7d1cb6fd267130f006",
    0,
    false,
    true
  },
  {
    // old-style 25-word seed phrase -- valid
    "conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation conversation",
    "71162f207499bc16260957c36a6586bb931d54be33ff56b94d565dfedbb3c70e",
    "8454372096986c457f4e7dceef2f39b6050c35d87b31d9c9eb8d37bf8f1f430f",
    0,
    false,
    true
  },
  {
    // old-style 25-word seed phrase -- invalid word
    "dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew dew!",
    "",
    "",
    0,
    false,
    false
  },
  {
    // old-style 25-word seed phrase -- invalid word
    "six six six six six six six six six sex six six six six six six six six six six six six six six six",
    "",
    "",
    0,
    false,
    false
  },
  {
    // new-style 26-word seed phrase -- invalid word
    "six six six six six six six six six six six six six six six six six six six six six six six six six sex",
    "",
    "",
    0,
    false,
    false
  },
  {
    // new-style 26-word seed phrase -- invalid checksum
    "six six six six six six six six six six six six six six six six six six six six six six six six six six",
    "",
    "",
    0,
    false,
    false
  },
  {
    // new-style 26-word seed phrase - valid
    "six six six six six six six six six six six six six six six six six six six six six six six six six frown",
    "F54F61E3B974AD86171AE4944205C7BD0395BD7845899CDA8B1FBC5C947BB402",
    "A18715058BBD914959C3A735B2022E9AE1D04452BC1FAD9E63C53668B7F57907",
    1922832000,
    false,
    true
  },
  {
    // new-style 26-word seed phrase auditable - valid
    "six six six six six six six six six six six six six six six six six six six six six six six six six grace",
    "F54F61E3B974AD86171AE4944205C7BD0395BD7845899CDA8B1FBC5C947BB402",
    "A18715058BBD914959C3A735B2022E9AE1D04452BC1FAD9E63C53668B7F57907",
    1922832000,
    true,
    true
  },

};

TEST(wallet_seed, basic_test) 
{
  for (size_t i = 0; i < sizeof wallet_seed_entries / sizeof wallet_seed_entries[0]; ++i)
  {
    const wallet_seed_entry& wse = wallet_seed_entries[i];
    currency::account_base acc;
    bool r = false;
    try
    {
      r = acc.restore_from_seed_phrase(wse.seed_phrase, "");
      if (r)
      {
        for (size_t j = 0; j != 100; j++)
        {
          //generate random password
          std::string pass = epee::string_tools::pod_to_hex(crypto::cn_fast_hash(&j, sizeof(j)));          
          pass.resize(std::min(j, (size_t)40));

          //get secured seed
          std::string secured_seed = acc.get_seed_phrase(pass);

          currency::account_base acc2{};
          if (!pass.empty())
          {
            //try to restore it without password(should fail)
            bool r_fail = acc2.restore_from_seed_phrase(secured_seed, "");
            ASSERT_EQ(r_fail, false);
          }

          //try to restore it with wrong password
          bool r_fake_pass = acc2.restore_from_seed_phrase(secured_seed, "fake_password");
          if (r_fake_pass)
          {
            //accidentally checksumm matched(quite possible)
            ASSERT_EQ(false, acc2.get_keys() == acc.get_keys());
          }

          //try to restore it from right password
          currency::account_base acc3;
          bool r_true_res = acc3.restore_from_seed_phrase(secured_seed, pass);
          ASSERT_EQ(true, r_true_res);
          r = acc3.get_keys() == acc.get_keys();
          ASSERT_TRUE(r);

        }
      }
    }
    catch (...)
    {
      r = false;
    }
    ASSERT_EQ(r, wse.valid);

    if (r)
    {
      if (wse.timestamp)
      {
        ASSERT_EQ(wse.timestamp, acc.get_createtime());
      }

      ASSERT_EQ(wse.auditable, acc.get_public_address().is_auditable());

      // check keys
      crypto::secret_key v, s;
      ASSERT_TRUE(epee::string_tools::parse_tpod_from_hex_string(wse.spend_secret_key, s));
      ASSERT_EQ(s, acc.get_keys().spend_secret_key);

      ASSERT_TRUE(epee::string_tools::parse_tpod_from_hex_string(wse.view_secret_key, v));
      ASSERT_EQ(v, acc.get_keys().view_secret_key);
    }

  }

}

TEST(wallet_seed, word_from_timestamp)
{
  //timestamp = 0; use_password = false
  ASSERT_EQ("like", currency::get_word_from_timestamp(0, false));

  // timestamp = 0; use_password = true
  ASSERT_EQ("among", currency::get_word_from_timestamp(0, true));

  // timestamp = WALLET_BRAIN_DATE_OFFSET = 1543622400; use_password = false
  ASSERT_EQ("like", currency::get_word_from_timestamp(1543622400, false));

  // timestamp = WALLET_BRAIN_DATE_OFFSET = 1543622400; use_password = true
  ASSERT_EQ("among", currency::get_word_from_timestamp(1543622400, true));

  // timestamp = WALLET_BRAIN_DATE_OFFSET - 1 = 1543622399; use_password = false
  ASSERT_EQ("like", currency::get_word_from_timestamp(1543622399, false));

  // timestamp = WALLET_BRAIN_DATE_OFFSET + 1 = 1543622401; use_password = false
  ASSERT_EQ("like", currency::get_word_from_timestamp(1543622401, false));

  // timestamp = WALLET_BRAIN_DATE_OFFSET + 1 = 1543622401; use_password = true
  ASSERT_EQ("among", currency::get_word_from_timestamp(1543622401, true));

  /*
    Values get_word_from_timestamp(1, true),
    get_word_from_timestamp(1543622401, true) must be equal.
  */

  ASSERT_EQ("among", currency::get_word_from_timestamp(1, true));
  ASSERT_EQ(currency::get_word_from_timestamp(1, true),
            currency::get_word_from_timestamp(1543622401, true));

  /*
    2027462399 is the largest timestamp argument value under which the
    inequality weeks_count < WALLET_BRAIN_DATE_MAX_WEEKS_COUNT is satisfied.

    timestamp = 2027462399
    date_offset = timestamp - WALLET_BRAIN_DATE_OFFSET = 483839999
    weeks_count = date_offset / WALLET_BRAIN_DATE_QUANTUM = 799
    WALLET_BRAIN_DATE_MAX_WEEKS_COUNT = 800
    WALLET_BRAIN_DATE_QUANTUM = 604800

    floor(483839999 / 604800) = 799
    floor(483840000 / 604800) = 800
  */

  // weeks_count_32 = 799; wordsArray[799] = "ugly"
  ASSERT_EQ("ugly", currency::get_word_from_timestamp(2027462399, false));

  // weeks_count_32 = 799 + 800 = 1599; wordsArray[1599] = "moan"
  ASSERT_EQ("moan", currency::get_word_from_timestamp(2027462399, true));

  /*
    If you pass values ​​>= 2027462399 + 1, then the inequality
    weeks_count < WALLET_BRAIN_DATE_MAX_WEEKS_COUNT is not satisfied. The
    function throws an exception.
  */

  EXPECT_THROW(currency::get_word_from_timestamp(2027462400, false),
               std::runtime_error);

  EXPECT_THROW(currency::get_word_from_timestamp(2027462400, true),
               std::runtime_error);
}

TEST(wallet_seed, timestamp_from_word)
{
  {
    // WALLET_BRAIN_DATE_OFFSET = 1543622400

    {
      bool password_used{false};

      ASSERT_EQ(1543622400,
                currency::get_timestamp_from_word("like", password_used));
      ASSERT_FALSE(password_used);
    }

    {
      bool password_used{true};

      ASSERT_EQ(1543622400,
                currency::get_timestamp_from_word("like", password_used));
      ASSERT_FALSE(password_used);
    }
  }

  {
    // WALLET_BRAIN_DATE_OFFSET = 1543622400

    {
      bool password_used{true};

      ASSERT_EQ(1543622400,
                currency::get_timestamp_from_word("among", password_used));
      ASSERT_TRUE(password_used);
    }

    {
      bool password_used{false};

      ASSERT_EQ(1543622400,
                currency::get_timestamp_from_word("among", password_used));
      ASSERT_TRUE(password_used);
    }
  }

  {
    // (1625 - 800) * 604800 + 1543622400 = 2042582400

    {
      bool password_used{false};

      ASSERT_EQ(2026857600,
                currency::get_timestamp_from_word("ugly", password_used));
      ASSERT_FALSE(password_used);
    }

    {
      bool password_used{true};

      ASSERT_EQ(2026857600,
                currency::get_timestamp_from_word("ugly", password_used));
      ASSERT_FALSE(password_used);
    }
  }

  {
    // (1625 - 800) * 604800 + 1543622400 = 2042582400

    {
      bool password_used{false};

      ASSERT_EQ(2042582400,
                currency::get_timestamp_from_word("weary", password_used));
      ASSERT_TRUE(password_used);
    }

    {
      bool password_used{true};

      ASSERT_EQ(2042582400,
                currency::get_timestamp_from_word("weary", password_used));
      ASSERT_TRUE(password_used);
    }
  }
}
