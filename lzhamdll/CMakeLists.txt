cmake_minimum_required(VERSION 3.16)
PROJECT(lzhamdll)
option(BUILD_X64 "build 64-bit" TRUE)
option(BUILD_LZHAMDLL_SHARED "Build lzhamdll as a shared library even when BUILD_SHARED_LIBS=OFF" OFF)

message("Initial BUILD_X64=${BUILD_X64}")
message("Initial CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}")

if( NOT CMAKE_BUILD_TYPE )
  set( CMAKE_BUILD_TYPE Release )
endif( NOT CMAKE_BUILD_TYPE )

message( ${PROJECT_NAME} " build type: " ${CMAKE_BUILD_TYPE} )

if (BUILD_X64)
message("Building 64-bit")
else()
message("Building 32-bit")
endif(BUILD_X64)

# Compiler flags: use proper flags per compiler
if(MSVC)
  # MSVC debug flags
  set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} /W3 /Zi")
  set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} /W3 /Zi")
  # MSVC release flags
  set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /O2 /Ot /DNDEBUG")
  set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} /O2 /DNDEBUG")
  # No GCC-only compile flags for MSVC
  set(GCC_COMPILE_FLAGS "")
else()
  # GCC/Clang flags
  set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -Wall -Wextra")
  set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g -Wall -Wextra")

  set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -Wall -Wextra -O3 -fomit-frame-pointer -fexpensive-optimizations")
  set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -Wall -Wextra")

  # -fno-strict-aliasing is *required* to compile LZHAM on GCC/Clang
  set(GCC_COMPILE_FLAGS "-fno-strict-aliasing -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64")
  if (NOT BUILD_X64)
    set(GCC_COMPILE_FLAGS "${GCC_COMPILE_FLAGS} -m32")
  endif()
endif()

set(SRC_LIST 
  lzham_api.cpp)

include_directories(
${PROJECT_SOURCE_DIR}/../lzhamdecomp
    ${PROJECT_SOURCE_DIR}/../lzhamcomp
${PROJECT_SOURCE_DIR}/../include)

if (BUILD_LZHAMDLL_SHARED)
  add_library(${PROJECT_NAME} SHARED ${SRC_LIST})
else()
  add_library(${PROJECT_NAME} ${SRC_LIST})
endif()

# Ensure the produced DLL filename matches what the loader expects.
# Use architecture-specific base name (lzham_x64 / lzham_x86) and append 'D'
# for Debug builds via OUTPUT_NAME_DEBUG.
if (BUILD_X64)
  set(LZHAM_DLL_BASENAME "lzham_x64")
else()
  set(LZHAM_DLL_BASENAME "lzham_x86")
endif()

set_target_properties(${PROJECT_NAME} PROPERTIES
   OUTPUT_NAME ${LZHAM_DLL_BASENAME}
   OUTPUT_NAME_DEBUG "${LZHAM_DLL_BASENAME}D"
)

# When building the unified C API DLL (lzhamdll) export the public C symbols.
target_compile_definitions(${PROJECT_NAME} PRIVATE LZHAM_DLL_EXPORTS)

# Link appropriately
if(MSVC)
  # Link against both lzhamcomp and lzhamdecomp. lzhamcomp depends on lzhamdecomp,
  # but the import library for lzhamcomp does not re-export lzhamdecomp symbols,
  # so consumers (lzhamdll) must link to both.
  target_link_libraries(${PROJECT_NAME} PRIVATE lzhamcomp lzhamdecomp)
else()
  target_link_libraries(${PROJECT_NAME} PRIVATE lzhamcomp lzhamdecomp pthread)
endif()

# Install rules
if(NOT MSVC)
  install(TARGETS ${PROJECT_NAME} LIBRARY DESTINATION lib${LIB_SUFFIX} ARCHIVE DESTINATION lib${LIB_SUFFIX} RUNTIME DESTINATION bin)
else()
  install(TARGETS ${PROJECT_NAME} ARCHIVE DESTINATION lib${LIB_SUFFIX} RUNTIME DESTINATION bin)
endif()

# Apply GCC_COMPILE_FLAGS only affects non-MSVC builds (it's empty on MSVC)
set(CMAKE_C_FLAGS  "${CMAKE_C_FLAGS} ${GCC_COMPILE_FLAGS}")
set(CMAKE_C_FLAGS_RELEASE  "${CMAKE_C_FLAGS_RELEASE} ${GCC_COMPILE_FLAGS} -DNDEBUG")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} ${GCC_COMPILE_FLAGS} -D_DEBUG")

set(CMAKE_CXX_FLAGS  "${CMAKE_CXX_FLAGS} ${GCC_COMPILE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELEASE  "${CMAKE_CXX_FLAGS_RELEASE} ${GCC_COMPILE_FLAGS} -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} ${GCC_COMPILE_FLAGS} -D_DEBUG")

## lzhamdll should export its own public C API, but do not reuse LZHAM_EXPORTS
## here because that macro is used to export symbols from lzhamdecomp. If the
## top-level DLL needs to export additional symbols, introduce a separate
## export macro for lzhamdll instead. For now, don't define LZHAM_EXPORTS here.
