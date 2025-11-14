# PROJECT(lzham)
cmake_minimum_required(VERSION 3.16)
option(BUILD_X64 "build 64-bit" ON)
option(BUILD_SHARED_LIBS "build shared/static libs" ON)

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
