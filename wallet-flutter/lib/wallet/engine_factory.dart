// Picks the wallet engine. dart:ffi does not exist on the web, so the native implementation is only imported where
// it does; the web build gets the stub (demo engine now, the WebAssembly engine in a later phase).
export 'engine_factory_stub.dart'
    if (dart.library.ffi) 'engine_factory_native.dart';
