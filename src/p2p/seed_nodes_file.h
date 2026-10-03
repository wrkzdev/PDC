// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#pragma once

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>

// Optional "seed_nodes.txt" in the data directory: extra seed nodes without rebuilding the daemon.
//
//   # one host:port per line, host is an IPv4 address or a DNS name
//   seed1.example.org:19121
//   203.0.113.7:19121   # trailing comments are allowed
//
// Blank lines and lines starting with '#' are ignored. Malformed lines are skipped and reported back
// so the caller can log them; they never abort startup. This only affects which peers a node tries
// first; it has no influence on consensus.

namespace nodetool
{
  const char* const P2P_SEED_NODES_FILENAME = "seed_nodes.txt";
  const size_t P2P_SEED_NODES_FILE_MAX_ENTRIES = 16;      // each entry costs a blocking DNS lookup at startup
  const size_t P2P_SEED_NODES_FILE_MAX_SIZE = 64 * 1024;  // refuse to parse anything bigger

  struct seed_nodes_parse_result
  {
    std::vector<std::string> entries;   // normalized "host:port"
    std::vector<std::string> rejected;  // original (trimmed) text of lines that were skipped
  };

  inline std::string seed_nodes_trim(const std::string& s)
  {
    size_t b = 0, e = s.size();
    while (b < e && std::isspace(static_cast<unsigned char>(s[b]))) ++b;
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) --e;
    return s.substr(b, e - b);
  }

  inline bool seed_nodes_is_valid_host(const std::string& host)
  {
    if (host.empty() || host.size() > 253)
      return false;
    for (char c : host)
    {
      const unsigned char u = static_cast<unsigned char>(c);
      if (!(std::isalnum(u) || c == '.' || c == '-' || c == '_'))
        return false;
    }
    return host.front() != '.' && host.front() != '-' && host.back() != '-';
  }

  inline bool seed_nodes_parse_port(const std::string& s, unsigned& port)
  {
    if (s.empty() || s.size() > 5)
      return false;
    for (char c : s)
      if (!std::isdigit(static_cast<unsigned char>(c)))
        return false;
    port = static_cast<unsigned>(std::strtoul(s.c_str(), nullptr, 10));
    return port >= 1 && port <= 65535;
  }

  inline seed_nodes_parse_result parse_seed_nodes_text(const std::string& text)
  {
    seed_nodes_parse_result result;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line))
    {
      const size_t hash = line.find('#');
      if (hash != std::string::npos)
        line.erase(hash);
      line = seed_nodes_trim(line);
      if (line.empty())
        continue;

      const size_t colon = line.find_last_of(':');
      unsigned port = 0;
      if (colon == std::string::npos || colon == 0 ||
          !seed_nodes_is_valid_host(line.substr(0, colon)) ||
          !seed_nodes_parse_port(line.substr(colon + 1), port))
      {
        result.rejected.push_back(line);
        continue;
      }

      const std::string entry = line.substr(0, colon) + ":" + std::to_string(port);
      bool duplicate = false;
      for (const std::string& e : result.entries)
        duplicate = duplicate || e == entry;
      if (duplicate)
        continue;

      if (result.entries.size() >= P2P_SEED_NODES_FILE_MAX_ENTRIES)
      {
        result.rejected.push_back(line);
        continue;
      }
      result.entries.push_back(entry);
    }
    return result;
  }

  // Missing file is not an error: returns false with no entries.
  inline bool load_seed_nodes_file(const std::string& path, seed_nodes_parse_result& result)
  {
    result = seed_nodes_parse_result();
    std::ifstream f(path.c_str(), std::ios::binary);
    if (!f.is_open())
      return false;
    std::string text((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (text.size() > P2P_SEED_NODES_FILE_MAX_SIZE)
    {
      result.rejected.push_back("<file too large>");
      return true;
    }
    result = parse_seed_nodes_text(text);
    return true;
  }
}
