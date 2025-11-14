cmake_minimum_required(VERSION 3.16)
PROJECT(lzhamcore)
option(BUILD_X64 "build 64-bit" TRUE)

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

# Compiler flags: mirror lzhamdecomp's settings
if(MSVC)
  set(GCC_COMPILE_FLAGS "")
else()
  set(GCC_COMPILE_FLAGS "-fno-strict-aliasing -D_LARGEFILE64_SOURCE=1 -D_FILE_OFFSET_BITS=64")
  if (NOT BUILD_X64)
    set(GCC_COMPILE_FLAGS "${GCC_COMPILE_FLAGS} -m32")
  endif()
endif()

set(SRC_LIST
    ../lzhamdecomp/lzham_vector.cpp
    ../lzhamdecomp/lzham_symbol_codec.cpp
    ../lzhamdecomp/lzham_lzdecompbase.cpp
  ../lzhamdecomp/lzham_huffman_codes.cpp
  ../lzhamdecomp/lzham_prefix_coding.cpp
  ../lzhamlib/lzham_lib.cpp
    
    ../lzhamdecomp/lzham_vector.h
    ../lzhamdecomp/lzham_symbol_codec.h
    ../lzhamdecomp/lzham_lzdecompbase.h
)

include_directories(
    ${PROJECT_SOURCE_DIR}/../lzhamdecomp
    ${PROJECT_SOURCE_DIR}/../include
  ${PROJECT_SOURCE_DIR}/../lzhamcomp
)

add_library(${PROJECT_NAME} STATIC ${SRC_LIST})

# lzhamcore is an internal static library and should not define provider export
# macros itself. Exported/provider symbols live in the provider DLL targets
# (lzhamdecomp/lzhamcomp) which define LZHAM_DECOMP_EXPORTS or LZHAM_COMP_EXPORTS.

# Apply compile flags
set(CMAKE_C_FLAGS  "${CMAKE_C_FLAGS} ${GCC_COMPILE_FLAGS}")
set(CMAKE_C_FLAGS_RELEASE  "${CMAKE_C_FLAGS_RELEASE} ${GCC_COMPILE_FLAGS} -DNDEBUG")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} ${GCC_COMPILE_FLAGS} -D_DEBUG")

set(CMAKE_CXX_FLAGS  "${CMAKE_CXX_FLAGS} ${GCC_COMPILE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELEASE  "${CMAKE_CXX_FLAGS_RELEASE} ${GCC_COMPILE_FLAGS} -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} ${GCC_COMPILE_FLAGS} -D_DEBUG")

install(TARGETS ${PROJECT_NAME} ARCHIVE DESTINATION lib RUNTIME DESTINATION bin)
