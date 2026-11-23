#ifndef SHM_VAR_H
#define SHM_VAR_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
  #ifdef SHMVAR_EXPORTS
    #define SHMVAR_API __declspec(dllexport)
  #else
    #define SHMVAR_API __declspec(dllimport)
  #endif
#else
  #define SHMVAR_API
#endif

// Return codes
#define SHMVAR_OK             0
#define SHMVAR_ERR_INVALID_ARG -1
#define SHMVAR_ERR_NOT_INIT   -2
#define SHMVAR_ERR_SYS_FAIL   -3
#define SHMVAR_ERR_NOT_FOUND  -4
#define SHMVAR_ERR_NO_MEM     -5
#define SHMVAR_ERR_BUF_TOO_SMALL -6
#define SHMVAR_ERR_TYPE_MISMATCH -7
#define SHMVAR_TIMEOUT        -8

// Value types
typedef enum {
    SHMVAR_TYPE_NONE = 0,
    SHMVAR_TYPE_INT = 1,
    SHMVAR_TYPE_DOUBLE = 2,
    SHMVAR_TYPE_STRING = 3,
    SHMVAR_TYPE_BYTES = 4
} ShmVarType;

/**
 * Initialize / attach to the named shared memory mapping.
 * @param mapName Name of the shared memory object.
 * @param initialSize Initial size in bytes (e.g. 16MB = 16*1024*1024). Used if creating new.
 * @return SHMVAR_OK (0) on success, or error code < 0.
 */
SHMVAR_API int32_t ShmVar_Init(const char* mapName, size_t initialSize);

/**
 * Close and detach from the current shared memory mapping.
 * @return SHMVAR_OK (0) on success.
 */
SHMVAR_API int32_t ShmVar_Close(void);

/**
 * Set a 64-bit signed integer.
 */
SHMVAR_API int32_t ShmVar_SetInt(const char* key, int64_t val);

/**
 * Get a 64-bit signed integer.
 */
SHMVAR_API int32_t ShmVar_GetInt(const char* key, int64_t* outVal);

/**
 * Set a 64-bit double precision float.
 */
SHMVAR_API int32_t ShmVar_SetDouble(const char* key, double val);

/**
 * Get a 64-bit double precision float.
 */
SHMVAR_API int32_t ShmVar_GetDouble(const char* key, double* outVal);

/**
 * Set a null-terminated UTF-8 string.
 */
SHMVAR_API int32_t ShmVar_SetStr(const char* key, const char* str);

/**
 * Get a string. If buf is NULL or bufSize too small, returns SHMVAR_ERR_BUF_TOO_SMALL,
 * and outLen receives required bytes (including null terminator).
 */
SHMVAR_API int32_t ShmVar_GetStr(const char* key, char* buf, size_t bufSize, size_t* outLen);

/**
 * Set arbitrary binary payload.
 */
SHMVAR_API int32_t ShmVar_SetBytes(const char* key, const void* data, size_t size);

/**
 * Get arbitrary binary payload. If buf is NULL or bufSize too small, returns SHMVAR_ERR_BUF_TOO_SMALL,
 * and outLen receives actual payload length.
 */
SHMVAR_API int32_t ShmVar_GetBytes(const char* key, void* buf, size_t bufSize, size_t* outLen);

/**
 * Delete a key-value entry.
 */
SHMVAR_API int32_t ShmVar_Delete(const char* key);

/**
 * Wait for any variable change notification (via Win32 Event).
 * @param timeoutMs Timeout in milliseconds (e.g. INFINITE = 0xFFFFFFFF).
 * @return SHMVAR_OK (0) on signaled, SHMVAR_TIMEOUT on timeout, or error code < 0.
 */
SHMVAR_API int32_t ShmVar_WaitForChange(uint32_t timeoutMs);

/**
 * Query variable type and data size.
 */
SHMVAR_API int32_t ShmVar_GetType(const char* key, int32_t* outType, size_t* outSize);

/**
 * Snapshot all live keys as consecutive null-terminated UTF-8 strings.
 * outLen receives the required/used bytes; an empty map uses zero bytes.
 */
SHMVAR_API int32_t ShmVar_GetKeys(char* buf, size_t bufSize, size_t* outLen);

#ifdef __cplusplus
}
#endif

#endif // SHM_VAR_H
