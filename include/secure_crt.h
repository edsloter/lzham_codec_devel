/* Portable secure CRT helpers
 * Provides fopen_secure, tmpfile_secure, GETENV and safe_sprintf wrapper usable from C and C++.
 */
#ifndef LZHAM_SECURE_CRT_H
#define LZHAM_SECURE_CRT_H

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#ifdef _MSC_VER

static inline FILE* fopen_secure(const char *pFilename, const char* pMode)
{
    FILE *pFile = NULL;
    if (fopen_s(&pFile, pFilename, pMode) == 0)
        return pFile;
    return NULL;
}

static inline FILE* tmpfile_secure(void)
{
    FILE *pFile = NULL;
    if (tmpfile_s(&pFile) == 0)
        return pFile;
    return NULL;
}

static inline char* getenv_dup(const char *pName)
{
    char *buf = NULL;
    size_t len = 0;
    if (_dupenv_s(&buf, &len, pName) == 0 && buf)
        return buf; // caller must free()
    return NULL;
}

static inline int safe_sprintf(char *buf, size_t bufsize, const char *fmt, ...)
{
    int r;
    va_list args;
    va_start(args, fmt);
    r = vsprintf_s(buf, bufsize, fmt, args);
    va_end(args);
    return r;
}

#else // non-MSVC

static inline FILE* fopen_secure(const char *pFilename, const char* pMode)
{
    return fopen(pFilename, pMode);
}

static inline FILE* tmpfile_secure(void)
{
    return tmpfile();
}

static inline char* getenv_dup(const char *pName)
{
    return getenv(pName);
}

static inline int safe_sprintf(char *buf, size_t bufsize, const char *fmt, ...)
{
    int r;
    va_list args;
    va_start(args, fmt);
    r = vsnprintf(buf, bufsize, fmt, args);
    va_end(args);
    return r;
}

#endif

#define SAFE_SPRINTF(buf, bufsize, fmt, ...) safe_sprintf((buf), (bufsize), (fmt), __VA_ARGS__)
#define GETENV_DUP(name) getenv_dup(name)

#endif // LZHAM_SECURE_CRT_H
