# CMake toolchain file: cross-compile for 64-bit Windows from Linux with MinGW-w64 (posix threads).
# Used by the win-build stage of utils/docker/Dockerfile.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER   x86_64-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)
set(CMAKE_RC_COMPILER  x86_64-w64-mingw32-windres)

# Boost and OpenSSL are passed explicitly (BOOST_ROOT, OPENSSL_ROOT_DIR); BOTH lets CMake use those absolute prefixes as given.
# Programs are only ever taken from the host.
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32 /opt/boost-win /opt/openssl-win)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# Windows API level: Vista or newer is needed by libmdbx and Boost.Asio (the MSVC build uses 0x0600 as well)
set(CMAKE_C_FLAGS_INIT   "-D_WIN32_WINNT=0x0601 -DWINVER=0x0601")
set(CMAKE_CXX_FLAGS_INIT "-D_WIN32_WINNT=0x0601 -DWINVER=0x0601")
