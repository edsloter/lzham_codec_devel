cmake_minimum_required(VERSION 3.16)
PROJECT(lzhamtest)
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
    timer.cpp
    timer.h
    lzhamtest.cpp)

include_directories(
${PROJECT_SOURCE_DIR}/../lzhamdecomp
    ${PROJECT_SOURCE_DIR}/../lzhamcomp
${PROJECT_SOURCE_DIR}/../include)

if (CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin_linux)
endif()

add_executable(${PROJECT_NAME} ${SRC_LIST})

# Configure static vs shared behavior for the test app based on BUILD_SHARED_LIBS.
# When building against shared libraries, define LZHAM_USE_LZHAM_DLL=1; when
# building static, define LZHAM_USE_LZHAM_DLL=0 and LZHAM_STATIC_LIB=1.
if (BUILD_SHARED_LIBS)
  message("Configuring lzhamtest to use shared LZHAM DLLs")
  target_compile_definitions(${PROJECT_NAME} PRIVATE LZHAM_USE_LZHAM_DLL=1)
  # When using shared libs we don't set LZHAM_STATIC_LIB
  target_link_libraries(${PROJECT_NAME} PRIVATE lzhamdll)
else()
  message("Configuring lzhamtest to use static LZHAM libs")
  target_compile_definitions(${PROJECT_NAME} PRIVATE LZHAM_STATIC_LIB=1 LZHAM_USE_LZHAM_DLL=0)
  # Link to static lzham libraries (lzhamcomp and lzhamdecomp). These targets depend on lzhamcore.
  # lzhamcore is a *static* archive containing lzham_lib.cpp, which calls into
  # lzham::lzham_lib_z_*() implemented in lzhamcomp/lzhamdecomp, so the three
  # archives reference each other. GNU ld resolves a single left-to-right pass
  # only, so tell it to rescan the group until it converges. MSVC doesn't care
  # about archive ordering, and doesn't understand LINK_GROUP.
  if (MSVC)
    target_link_libraries(${PROJECT_NAME} PRIVATE lzhamcomp lzhamdecomp)
  elseif (CMAKE_VERSION VERSION_GREATER_EQUAL 3.24)
    target_link_libraries(${PROJECT_NAME} PRIVATE "$<LINK_GROUP:RESCAN,lzhamcomp,lzhamdecomp,lzhamcore>")
  else()
    # Older CMake: list the archives twice so the second pass picks up whatever
    # the first pass left dangling.
    target_link_libraries(${PROJECT_NAME} PRIVATE lzhamcomp lzhamdecomp lzhamcore lzhamcomp lzhamdecomp lzhamcore)
  endif()
endif()

# Apply GCC_COMPILE_FLAGS only affects non-MSVC builds (it's empty on MSVC)
set(CMAKE_C_FLAGS  "${CMAKE_C_FLAGS} ${GCC_COMPILE_FLAGS}")
set(CMAKE_C_FLAGS_RELEASE  "${CMAKE_C_FLAGS_RELEASE} ${GCC_COMPILE_FLAGS} -DNDEBUG")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} ${GCC_COMPILE_FLAGS} -D_DEBUG")

set(CMAKE_CXX_FLAGS  "${CMAKE_CXX_FLAGS} ${GCC_COMPILE_FLAGS}")
set(CMAKE_CXX_FLAGS_RELEASE  "${CMAKE_CXX_FLAGS_RELEASE} ${GCC_COMPILE_FLAGS} -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} ${GCC_COMPILE_FLAGS} -D_DEBUG")
