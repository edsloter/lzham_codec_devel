# LZHAMExportPolicy.cmake
# Centralizes export/static build policy for LZHAM targets.
# Usage: include("${CMAKE_SOURCE_DIR}/cmake/LZHAMExportPolicy.cmake")
#        lzham_configure_export_policy()
#        lzham_set_target_export_macro(<target> <EXPORT_MACRO>)
#
# This file defines:
# - lzham_configure_export_policy(): defines LZHAM_USE_STATIC when BUILD_SHARED_LIBS=OFF
# - lzham_set_target_export_macro(<target> <EXPORT_MACRO>): when building shared libs,
#   sets the given compile definition on <target> (e.g. LZHAM_DECOMP_EXPORTS).

function(lzham_configure_export_policy)
  if(NOT BUILD_SHARED_LIBS)
    message(STATUS "LZHAM: Configuring static build; defining LZHAM_USE_STATIC")
    # Define a macro consumed by headers so they avoid __declspec(dllimport)
    add_compile_definitions(LZHAM_USE_STATIC)
  else()
    message(STATUS "LZHAM: Configuring shared build; using per-target export macros")
  endif()
endfunction()

# Helper: attach an export macro definition to a target when building shared libs.
# Example: lzham_set_target_export_macro(lzhamdecomp LZHAM_DECOMP_EXPORTS)
function(lzham_set_target_export_macro target export_macro)
  if(BUILD_SHARED_LIBS)
    if(TARGET ${target})
      target_compile_definitions(${target} PRIVATE ${export_macro})
    else()
      message(WARNING "lzham_set_target_export_macro: target '${target}' not defined yet")
    endif()
  endif()
endfunction()
