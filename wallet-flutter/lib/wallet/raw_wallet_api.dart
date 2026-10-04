// String-in / string-out surface of the C++ wallet, one method per function of plain_wallet_api.h
// (src/wallet/plain_wallet_api.h). A backend implements this once:
//   - desktop (and later mobile): dart:ffi calls into a native library built from the wallet in remote-only mode;
//   - web: the same C++ compiled to WebAssembly, called through dart:js_interop.
// Everything above this interface (InvokeWalletCore and the UI) is shared by all targets.

abstract class RawWalletApi {
  /// plain_wallet::init(address, working_dir, log_level). [nodeAddress] is e.g. "https://node.example.org:19211".
  Future<String> init(String nodeAddress, String workingDir, int logLevel);

  /// plain_wallet::generate / restore / open: JSON `{"result":{"wallet_id":N,"seed":"..."}}` or `{"error":{"code":"..."}}`.
  Future<String> generate(String path, String password);
  Future<String> restore(
    String seed,
    String path,
    String password,
    String seedPassword,
  );
  Future<String> open(String path, String password);

  Future<String> closeWallet(int walletId);

  /// plain_wallet::get_wallet_status: sync heights and state.
  Future<String> getWalletStatus(int walletId);

  /// plain_wallet::invoke: [jsonRpcRequest] is a complete JSON-RPC 2.0 request for the wallet RPC server
  /// (`{"jsonrpc":"2.0","id":0,"method":"getbalance","params":{}}`); the reply is the JSON-RPC response.
  Future<String> invoke(int walletId, String jsonRpcRequest);

  /// Stops the engine and its threads. Must be called before the process exits: on Windows the engine cannot do it from
  /// its static destructor and a process that exits without it can hang forever.
  Future<String> shutdown();
}
