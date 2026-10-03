// Copyright (c) 2026 PDC
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

// JSON-RPC method allowlist for a public PDC node (njs, loaded by nginx.conf).
//
// Only read-only calls a wallet or a light explorer needs are forwarded. Everything that controls the
// node (submitblock*, getblocktemplate, reset_transaction_pool, remove_tx_from_pool, ...) or that hands
// a secret key to the node (decrypt_tx_details takes a tx secret key, find_outs_in_recent_blocks takes a
// view key) is refused. Sending a transaction is the plain /sendrawtransaction URI.

var ALLOWED_METHODS = {
  'getinfo': 1,
  'getblockcount': 1,
  'getlastblockheader': 1,
  'getblockheaderbyheight': 1,
  'getblockheaderbyhash': 1,
  'getrandom_outs3': 1,
  'get_current_core_tx_expiration_median': 1,
  'get_est_height_from_date': 1,
  'get_asset_info': 1,
  'get_assets_list': 1,
  'get_alias_details': 1,
  'get_alias_by_address': 1,
  'get_alias_reward': 1,
  'get_pool_info': 1,
  'get_tx_details': 1
};

function deny(r, status, id, code, message) {
  r.headersOut['Content-Type'] = 'application/json';
  r.return(status, JSON.stringify({ jsonrpc: '2.0', id: id, error: { code: code, message: message } }));
}

function count(haystack, needle) {
  var n = 0, i = haystack.indexOf(needle);
  while (i !== -1) { n++; i = haystack.indexOf(needle, i + needle.length); }
  return n;
}

function jsonrpc(r) {
  // The wallet engine's HTTP client (epee) sends its JSON-RPC calls as GET with a body, other clients use POST.
  if (r.method !== 'POST' && r.method !== 'GET') {
    deny(r, 405, null, -32600, 'POST or GET required');
    return;
  }

  var body = r.requestText;
  if (typeof body !== 'string' || body.length === 0) {
    deny(r, 400, null, -32700, 'Empty or oversized request body');
    return;
  }

  var req;
  try {
    req = JSON.parse(body);
  } catch (e) {
    deny(r, 400, null, -32700, 'Parse error');
    return;
  }
  if (req === null || typeof req !== 'object' || Array.isArray(req)) {
    deny(r, 400, null, -32600, 'Batch and non-object requests are not supported');
    return;
  }
  var id = (req.id === undefined) ? null : req.id;

  // The daemon's own JSON parser may resolve a repeated or escaped "method" key differently from JSON.parse
  // here, which would let a forbidden method hide behind an allowed one. The body is forwarded unchanged
  // (re-serializing would round-trip 64-bit amounts through doubles), so refuse anything ambiguous instead.
  if (body.indexOf('\\') !== -1 || count(body, '"method"') !== 1) {
    deny(r, 400, id, -32600, 'Ambiguous request');
    return;
  }

  if (typeof req.method !== 'string' || !Object.prototype.hasOwnProperty.call(ALLOWED_METHODS, req.method)) {
    deny(r, 403, id, -32601, 'Method not available on this public node');
    return;
  }

  r.subrequest('/_pdcd_jsonrpc', { method: 'POST', body: body }, function (reply) {
    r.headersOut['Content-Type'] = 'application/json';
    r.return(reply.status, reply.responseText);
  });
}

export default { jsonrpc };
