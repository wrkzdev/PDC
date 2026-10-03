// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "gtest/gtest.h"

#include <string>

#include "p2p/seed_nodes_file.h"

using namespace nodetool;

TEST(seed_nodes_file, parses_hosts_ips_comments_and_blank_lines)
{
  const std::string text =
    "# PDC seeds\n"
    "\n"
    "seed1.example.org:19121\n"
    "   203.0.113.7:19121   # trailing comment\r\n"
    "\t\n"
    "seed-2.example.org : 19121\n"  // spaces around ':' are not allowed
    "seed3.example.org:19121";      // no trailing newline
  seed_nodes_parse_result r = parse_seed_nodes_text(text);
  ASSERT_EQ(3u, r.entries.size());
  ASSERT_EQ("seed1.example.org:19121", r.entries[0]);
  ASSERT_EQ("203.0.113.7:19121", r.entries[1]);
  ASSERT_EQ("seed3.example.org:19121", r.entries[2]);
  ASSERT_EQ(1u, r.rejected.size());
}

TEST(seed_nodes_file, rejects_malformed_lines_without_aborting)
{
  const std::string text =
    "nocolon\n"
    ":19121\n"
    "host:\n"
    "host:0\n"
    "host:65536\n"
    "host:12x\n"
    "ho st:19121\n"
    "-bad.example.org:19121\n"
    "ok.example.org:19121\n";
  seed_nodes_parse_result r = parse_seed_nodes_text(text);
  ASSERT_EQ(1u, r.entries.size());
  ASSERT_EQ("ok.example.org:19121", r.entries[0]);
  ASSERT_EQ(8u, r.rejected.size());
}

TEST(seed_nodes_file, deduplicates_and_normalizes_port)
{
  seed_nodes_parse_result r = parse_seed_nodes_text("a.example.org:019121\na.example.org:19121\n");
  ASSERT_EQ(1u, r.entries.size());
  ASSERT_EQ("a.example.org:19121", r.entries[0]);
}

TEST(seed_nodes_file, caps_number_of_entries)
{
  std::string text;
  for (size_t i = 0; i < P2P_SEED_NODES_FILE_MAX_ENTRIES + 10; ++i)
    text += "h" + std::to_string(i) + ".example.org:19121\n";
  seed_nodes_parse_result r = parse_seed_nodes_text(text);
  ASSERT_EQ(P2P_SEED_NODES_FILE_MAX_ENTRIES, r.entries.size());
  ASSERT_EQ(10u, r.rejected.size());
}

TEST(seed_nodes_file, missing_file_is_not_an_error)
{
  seed_nodes_parse_result r;
  ASSERT_FALSE(load_seed_nodes_file("this/path/does/not/exist/seed_nodes.txt", r));
  ASSERT_TRUE(r.entries.empty());
}
