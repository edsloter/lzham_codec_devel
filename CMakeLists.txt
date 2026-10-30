# PROJECT(lzham)
cmake_minimum_required(VERSION 3.16)
option(BUILD_X64 "build 64-bit" ON)

# BUILD_SHARED_LIBS selects the *modular* shared layout (separate lzhamcomp,
# lzhamdecomp and lzhamdll shared objects). On Windows that also switches
# lzhamtest to its Win32 DLL loader. Off Windows that loader does not exist, so
# default to a static build there: it keeps a plain `cmake . && make install`
# working and produces a self-contained lzhamtest binary. Pass
# -DBUILD_SHARED_LIBS=ON explicitly if you only want the shared libraries, or
# use -DBUILD_LZHAMDLL_SHARED=ON for a single unified liblzham_x64.so.
if(WIN32)
  set(LZHAM_BUILD_SHARED_LIBS_DEFAULT ON)
else()
  set(LZHAM_BUILD_SHARED_LIBS_DEFAULT OFF)
endif()
option(BUILD_SHARED_LIBS "build shared/static libs" ${LZHAM_BUILD_SHARED_LIBS_DEFAULT})

# Centralize export/static policy and helper functions for LZHAM
include(${CMAKE_SOURCE_DIR}/cmake/LZHAMExportPolicy.cmake)
lzham_configure_export_policy()

add_subdirectory(lzhamcore)
add_subdirectory(lzhamdecomp)
add_subdirectory(lzhamcomp)
add_subdirectory(lzhamdll)
add_subdirectory(lzhamtest)

install(FILES include/lzham_dynamic_lib.h
              include/lzham_exports.inc
              include/lzham.h
              include/lzham_static_lib.h
              include/zlib.h
              DESTINATION include)
