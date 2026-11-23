#ifndef SHM_INTERNAL_H
#define SHM_INTERNAL_H

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <span>
#include <string_view>
#include <concepts>
#include <atomic>
#include <windows.h>
#include "shm_var.h"

namespace shm {

constexpr uint32_t SHM_MAGIC = 0x564D4853; // 'SHMV' in little endian
constexpr uint32_t SHM_VERSION = 1;
constexpr uint32_t HASH_BUCKET_COUNT = 4096; // 4096 hash buckets
constexpr uint32_t OFFSET_NIL = 0xFFFFFFFF;
constexpr uint64_t MAX_SHM_SIZE = 0xFFFFFFFFULL; // 4GB max due to 32-bit relative offsets

#pragma pack(push, 8)

// Header located at base of Shared Memory mapping
struct ShmHeader {
    uint32_t magic;           // SHM_MAGIC
    uint32_t version;         // SHM_VERSION
    uint64_t totalSize;       // Total size of mapping in bytes
    uint64_t freeOffset;      // Offset of dynamic bump pointer in heap
    uint64_t changeCount;     // Monotonic counter for change notifications
    uint32_t entryCount;      // Total live entries
    uint32_t reserved;
    uint32_t buckets[HASH_BUCKET_COUNT]; // Offset to head of linked list in each bucket
};

// POD union covering payload stored in shared memory
union ShmPayload {
    int64_t  intVal;          // SHMVAR_TYPE_INT
    double   doubleVal;       // SHMVAR_TYPE_DOUBLE
    uint32_t dataOffset;      // SHMVAR_TYPE_STRING or SHMVAR_TYPE_BYTES
};

// Node in hash map linked list
struct ShmNode {
    uint32_t nextOffset;      // OFFSET_NIL if end of bucket list
    uint32_t type;            // ShmVarType
    uint32_t keyLen;          // Length of key string (not including '\0')
    uint32_t dataLen;         // Length of payload in bytes
    ShmPayload payload;       // 8-byte union covering intVal, doubleVal, dataOffset
    uint32_t keyOffset;       // Offset to key string buffer
    uint32_t reserved;        // 8-byte alignment padding
};

#pragma pack(pop)

// Hash function: FNV-1a 32-bit (constexpr supported in C++23)
constexpr uint32_t HashKey(std::string_view key) noexcept {
    uint32_t hash = 2166136261u;
    for (char c : key) {
        hash ^= static_cast<uint8_t>(c);
        hash *= 16777619u;
    }
    return hash;
}

// 8-byte alignment helper
constexpr size_t Align8(size_t size) noexcept {
    return (size + 7) & ~static_cast<size_t>(7);
}

} // namespace shm

#endif // SHM_INTERNAL_H
