// File: lzham_decomp.h
// See Copyright Notice and license at the end of include/lzham.h
#pragma once
#include "lzham.h"

namespace lzham
{
   LZHAM_DECOMP_EXPORT void LZHAM_CDECL lzham_lib_set_memory_callbacks(lzham_realloc_func pRealloc, lzham_msize_func pMSize, void* pUser_data);
   
   LZHAM_DECOMP_EXPORT lzham_decompress_state_ptr LZHAM_CDECL lzham_lib_decompress_init(const lzham_decompress_params *pParams);

   LZHAM_DECOMP_EXPORT lzham_decompress_state_ptr LZHAM_CDECL lzham_lib_decompress_reinit(lzham_decompress_state_ptr pState, const lzham_decompress_params *pParams);

   LZHAM_DECOMP_EXPORT lzham_uint32 LZHAM_CDECL lzham_lib_decompress_deinit(lzham_decompress_state_ptr pState);

   LZHAM_DECOMP_EXPORT lzham_decompress_status_t LZHAM_CDECL lzham_lib_decompress(
      lzham_decompress_state_ptr pState,
      const lzham_uint8 *pIn_buf, size_t *pIn_buf_size, 
      lzham_uint8 *pOut_buf, size_t *pOut_buf_size,
      lzham_bool no_more_input_bytes_flag);
      
   LZHAM_DECOMP_EXPORT lzham_decompress_status_t LZHAM_CDECL lzham_lib_decompress_memory(const lzham_decompress_params *pParams, 
      lzham_uint8* pDst_buf, size_t *pDst_len, 
      const lzham_uint8* pSrc_buf, size_t src_len, lzham_uint32 *pAdler32);

   LZHAM_DECOMP_EXPORT int LZHAM_CDECL lzham_lib_z_inflateInit2(lzham_z_streamp pStream, int window_bits);
   LZHAM_DECOMP_EXPORT int LZHAM_CDECL lzham_lib_z_inflateInit(lzham_z_streamp pStream);
   LZHAM_DECOMP_EXPORT int LZHAM_CDECL lzham_lib_z_inflateReset(lzham_z_streamp pStream);
   LZHAM_DECOMP_EXPORT int LZHAM_CDECL lzham_lib_z_inflate(lzham_z_streamp pStream, int flush);
   LZHAM_DECOMP_EXPORT int LZHAM_CDECL lzham_lib_z_inflateEnd(lzham_z_streamp pStream);
   LZHAM_DECOMP_EXPORT int LZHAM_CDECL lzham_lib_z_uncompress(unsigned char *pDest, lzham_z_ulong *pDest_len, const unsigned char *pSource, lzham_z_ulong source_len);

   LZHAM_DECOMP_EXPORT const char * LZHAM_CDECL lzham_lib_z_error(int err);
   LZHAM_DECOMP_EXPORT lzham_z_ulong lzham_lib_z_adler32(lzham_z_ulong adler, const unsigned char *ptr, size_t buf_len);
   LZHAM_DECOMP_EXPORT lzham_z_ulong LZHAM_CDECL lzham_lib_z_crc32(lzham_z_ulong crc, const lzham_uint8 *ptr, size_t buf_len);

} // namespace lzham
