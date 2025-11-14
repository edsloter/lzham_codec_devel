cmake_minimum_required(VERSION 3.16)
PROJECT(lzhamcomp)
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
lzham_lzbase.cpp
lzham_lzbase.h
lzham_lzcomp.cpp
lzham_lzcomp_internal.cpp
lzham_lzcomp_internal.h
lzham_lzcomp_state.cpp
lzham_match_accel.cpp
lzham_match_accel.h
lzham_null_threading.h
lzham_pthreads_threading.cpp
lzham_pthreads_threading.h
lzham_threading.h)

### lzham_comp_wrappers.cpp was removed (wrappers not required)

if (WIN32)
  list (APPEND SRC_LIST lzham_win32_threading.cpp)
endif ()

include_directories(
${PROJECT_SOURCE_DIR}/../lzhamdecomp 
${PROJECT_SOURCE_DIR}/../include)

add_library(${PROJECT_NAME} ${SRC_LIST})

# Link to lzhamdecomp, and only link pthread on non-MSVC
if(MSVC)
  target_link_libraries(${PROJECT_NAME} PRIVATE lzhamdecomp lzhamcore)
else()
  target_link_libraries(${PROJECT_NAME} PRIVATE lzhamdecomp lzhamcore pthread)
endif()

# When building shared libs, export this project's public symbols from lzhamcomp
if(BUILD_SHARED_LIBS)
  target_compile_definitions(${PROJECT_NAME} PRIVATE LZHAM_COMP_EXPORTS)
endif()

## Do NOT set LZHAM_EXPORTS here. lzhamdecomp defines the symbols that should be
## exported when building shared libraries. Consumers (like lzhamcomp) must NOT
## define LZHAM_EXPORTS or they'll try to dllexport symbols they don't define.

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
