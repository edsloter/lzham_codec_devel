// Thin C++ namespace wrappers for C API functions so the namespaced
// `lzham::lzham_lib_*` symbols exist and can be exported by the comp
// library. These call the existing extern "C" functions defined in
// the module (e.g. lzham_lzcomp.cpp).
#include "lzham_comp.h"

namespace lzham
{

lzham_compress_state_ptr LZHAM_CDECL lzham_lib_compress_init(const lzham_compress_params *pParams)
{
   return ::lzham_lib_compress_init(pParams);
}

lzham_compress_state_ptr LZHAM_CDECL lzham_lib_compress_reinit(lzham_compress_state_ptr p)
{
   return ::lzham_lib_compress_reinit(p);
}

lzham_uint32 LZHAM_CDECL lzham_lib_compress_deinit(lzham_compress_state_ptr p)
{
   return ::lzham_lib_compress_deinit(p);
}

lzham_compress_status_t LZHAM_CDECL lzham_lib_compress(
   lzham_compress_state_ptr p,
   const lzham_uint8 *pIn_buf, size_t *pIn_buf_size,
   lzham_uint8 *pOut_buf, size_t *pOut_buf_size,
   lzham_bool no_more_input_bytes_flag)
{
   return ::lzham_lib_compress(p, pIn_buf, pIn_buf_size, pOut_buf, pOut_buf_size, no_more_input_bytes_flag);
}

lzham_compress_status_t LZHAM_CDECL lzham_lib_compress2(
   lzham_compress_state_ptr p,
   const lzham_uint8 *pIn_buf, size_t *pIn_buf_size,
   lzham_uint8 *pOut_buf, size_t *pOut_buf_size,
   lzham_flush_t flush_type)
{
   return ::lzham_lib_compress2(p, pIn_buf, pIn_buf_size, pOut_buf, pOut_buf_size, flush_type);
}

lzham_compress_status_t LZHAM_CDECL lzham_lib_compress_memory(const lzham_compress_params *pParams, lzham_uint8* pDst_buf, size_t *pDst_len, const lzham_uint8* pSrc_buf, size_t src_len, lzham_uint32 *pAdler32)
{
   return ::lzham_lib_compress_memory(pParams, pDst_buf, pDst_len, pSrc_buf, src_len, pAdler32);
}

int lzham_lib_z_deflateInit(lzham_z_streamp pStream, int level)
{
   return ::lzham_lib_z_deflateInit(pStream, level);
}

int lzham_lib_z_deflateInit2(lzham_z_streamp pStream, int level, int method, int window_bits, int mem_level, int strategy)
{
   return ::lzham_lib_z_deflateInit2(pStream, level, method, window_bits, mem_level, strategy);
}

int lzham_lib_z_deflateReset(lzham_z_streamp pStream)
{
   return ::lzham_lib_z_deflateReset(pStream);
}

int lzham_lib_z_deflate(lzham_z_streamp pStream, int flush)
{
   return ::lzham_lib_z_deflate(pStream, flush);
}

int lzham_lib_z_deflateEnd(lzham_z_streamp pStream)
{
   return ::lzham_lib_z_deflateEnd(pStream);
}

lzham_z_ulong lzham_lib_z_deflateBound(lzham_z_streamp pStream, lzham_z_ulong source_len)
{
   return ::lzham_lib_z_deflateBound(pStream, source_len);
}

int lzham_lib_z_compress2(unsigned char *pDest, lzham_z_ulong *pDest_len, const unsigned char *pSource, lzham_z_ulong source_len, int level)
{
   return ::lzham_lib_z_compress2(pDest, pDest_len, pSource, source_len, level);
}

int lzham_lib_z_compress(unsigned char *pDest, lzham_z_ulong *pDest_len, const unsigned char *pSource, lzham_z_ulong source_len)
{
   return ::lzham_lib_z_compress(pDest, pDest_len, pSource, source_len);
}

lzham_z_ulong lzham_lib_z_compressBound(lzham_z_ulong source_len)
{
   return ::lzham_lib_z_compressBound(source_len);
}

} // namespace lzham
