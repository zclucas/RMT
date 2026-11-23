#ifndef SHMVAR_EXPORTS
#define SHMVAR_EXPORTS
#endif

#define BUDDY_ALLOC_IMPLEMENTATION
#include "shm_var.h"
#include "shm_internal.h"
#include "shm_allocator.h"

#include <string>
#include <string_view>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <limits>
#include <type_traits>
#include <cstring>

namespace {

struct ShmContext {
    HANDLE hMapFile = nullptr;
    uint8_t* baseAddr = nullptr;
    size_t mappedSize = 0;
    HANDLE hMutex = nullptr;
    HANDLE hEvent = nullptr;
    std::string mapName;
    bool isCreator = false;
};

// Thread-safe in-process context managed by shared_mutex
static ShmContext g_ctx;
static std::shared_mutex g_lifecycleLock;

// RAII lock for Win32 cross-process Mutex
class CrossProcessLock {
public:
    explicit CrossProcessLock(HANDLE hMutex, DWORD timeoutMs = INFINITE)
        : m_hMutex(hMutex), m_acquired(false) {
        if (m_hMutex) {
            DWORD res = WaitForSingleObject(m_hMutex, timeoutMs);
            if (res == WAIT_OBJECT_0 || res == WAIT_ABANDONED) {
                m_acquired = true;
            }
        }
    }

    ~CrossProcessLock() {
        if (m_acquired && m_hMutex) {
            ReleaseMutex(m_hMutex);
        }
    }

    bool isLocked() const noexcept { return m_acquired; }

private:
    HANDLE m_hMutex;
    bool m_acquired;
};

// Convert relative offset to pointer in current process address space
template <typename T = void>
inline T* OffsetToPointer(uint8_t* base, uint32_t offset) noexcept {
    if (offset == shm::OFFSET_NIL) return nullptr;
    return reinterpret_cast<T*>(base + offset);
}

// Helper to construct local ShmBuddyAllocator adapter from header
inline shm::ShmBuddyAllocator MakeAllocator(shm::ShmHeader& header, uint8_t* base) noexcept {
    return shm::ShmBuddyAllocator(base, header.arenaOffset, header.arenaSize);
}

// Find existing node or bucket insertion point. keyHash can be provided if already computed.
static shm::ShmNode* FindNode(uint8_t* base, shm::ShmHeader* header, std::string_view key, uint32_t keyHash, uint32_t* outPrevOffset, uint32_t* outBucketIdx, uint32_t* outNodeOffset = nullptr) noexcept {
    uint32_t bucket = keyHash % shm::HASH_BUCKET_COUNT;
    if (outBucketIdx) *outBucketIdx = bucket;

    uint32_t prev = shm::OFFSET_NIL;
    uint32_t curr = header->buckets[bucket];

    while (curr != shm::OFFSET_NIL) {
        auto* node = OffsetToPointer<shm::ShmNode>(base, curr);
        if (!node) break;
        if (node->keyLen == key.size()) {
            const char* keyPtr = OffsetToPointer<const char>(base, node->keyOffset);
            if (keyPtr && key == std::string_view(keyPtr, node->keyLen)) {
                if (outPrevOffset) *outPrevOffset = prev;
                if (outNodeOffset) *outNodeOffset = curr;
                return node;
            }
        }
        prev = curr;
        curr = node->nextOffset;
    }

    if (outPrevOffset) *outPrevOffset = prev;
    if (outNodeOffset) *outNodeOffset = shm::OFFSET_NIL;
    return nullptr;
}

// Find or allocate a new ShmNode and key buffer via Buddy Allocator
static shm::ShmNode* GetOrCreateNode(shm::ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash) noexcept {
    uint32_t prevOffset = shm::OFFSET_NIL;
    uint32_t bucketIdx = 0;
    auto* node = FindNode(base, &header, key, keyHash, &prevOffset, &bucketIdx);
    if (node) {
        return node;
    }

    auto allocator = MakeAllocator(header, base);
    if (!allocator.IsValid()) return nullptr;

    uint32_t nodeOff = allocator.Allocate(sizeof(shm::ShmNode));
    if (nodeOff == shm::OFFSET_NIL) return nullptr;

    uint32_t keyOff = allocator.Allocate(key.size() + 1);
    if (keyOff == shm::OFFSET_NIL) {
        allocator.Free(nodeOff); // Clean rollback on key alloc failure
        return nullptr;
    }

    char* keyDst = OffsetToPointer<char>(base, keyOff);
    std::memcpy(keyDst, key.data(), key.size());
    keyDst[key.size()] = '\0';

    node = OffsetToPointer<shm::ShmNode>(base, nodeOff);
    node->nextOffset = header.buckets[bucketIdx];
    node->type = SHMVAR_TYPE_NONE;
    node->keyLen = static_cast<uint32_t>(key.size());
    node->dataLen = 0;
    node->payload.intVal = 0;
    node->keyOffset = keyOff;
    node->reserved = 0;

    header.buckets[bucketIdx] = nodeOff;
    header.entryCount++;

    return node;
}

// Template helper to set scalar values (int64_t or double)
template <typename T>
static int32_t SetScalarValue(shm::ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash, T val) noexcept {
    auto* node = GetOrCreateNode(header, base, key, keyHash);
    if (!node) return SHMVAR_ERR_NO_MEM;

    // If node was previously holding an allocated blob, free it
    if ((node->type == SHMVAR_TYPE_STRING || node->type == SHMVAR_TYPE_BYTES) &&
        node->payload.dataOffset != shm::OFFSET_NIL) {
        auto allocator = MakeAllocator(header, base);
        allocator.Free(node->payload.dataOffset);
        node->payload.dataOffset = shm::OFFSET_NIL;
    }

    if constexpr (std::is_same_v<T, int64_t>) {
        node->type = SHMVAR_TYPE_INT;
        node->dataLen = sizeof(int64_t);
        node->payload.intVal = val;
    } else {
        node->type = SHMVAR_TYPE_DOUBLE;
        node->dataLen = sizeof(double);
        node->payload.doubleVal = val;
    }
    return SHMVAR_OK;
}

// Common blob write logic with in-place overwrite & safe allocate-switch-free order
static int32_t SetBlobValue(shm::ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash, const void* data, size_t size, uint32_t type, bool nullTerminate) noexcept {
    auto* node = GetOrCreateNode(header, base, key, keyHash);
    if (!node) return SHMVAR_ERR_NO_MEM;

    size_t reqLen = nullTerminate ? (size + 1) : size;
    auto allocator = MakeAllocator(header, base);
    if (!allocator.IsValid()) return SHMVAR_ERR_SYS_FAIL;

    // Fast path: In-place overwrite if existing buffer is already large enough
    if ((node->type == SHMVAR_TYPE_STRING || node->type == SHMVAR_TYPE_BYTES) &&
        node->payload.dataOffset != shm::OFFSET_NIL && allocator.GetAllocSize(node->payload.dataOffset) >= reqLen) {
        if (data && size > 0) {
            void* dst = OffsetToPointer(base, node->payload.dataOffset);
            std::memcpy(dst, data, size);
        }
        if (nullTerminate) {
            char* dstChar = OffsetToPointer<char>(base, node->payload.dataOffset);
            dstChar[size] = '\0';
        }
        node->type = type;
        node->dataLen = static_cast<uint32_t>(reqLen);
        return SHMVAR_OK;
    }

    // Defensive reallocation order:
    // 1. Allocate new buffer first (if allocation fails, old data remains intact)
    uint32_t newOffset = shm::OFFSET_NIL;
    if (reqLen > 0) {
        newOffset = allocator.Allocate(reqLen);
        if (newOffset == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        // 2. Write new payload into new buffer
        if (data && size > 0) {
            void* dst = OffsetToPointer(base, newOffset);
            std::memcpy(dst, data, size);
        }
        if (nullTerminate) {
            char* dstChar = OffsetToPointer<char>(base, newOffset);
            dstChar[size] = '\0';
        }
    }

    // 3. Save old offset & switch to new buffer
    uint32_t oldOffset = shm::OFFSET_NIL;
    if (node->type == SHMVAR_TYPE_STRING || node->type == SHMVAR_TYPE_BYTES) {
        oldOffset = node->payload.dataOffset;
    }

    node->type = type;
    node->dataLen = static_cast<uint32_t>(reqLen);
    node->payload.dataOffset = newOffset;

    // 4. Finally free old buffer
    if (oldOffset != shm::OFFSET_NIL) {
        allocator.Free(oldOffset);
    }

    return SHMVAR_OK;
}

// Reliable notification via event signaling
inline void NotifyChange(shm::ShmHeader* header, HANDLE hEvent) noexcept {
    if (header) {
        header->changeCount++;
    }
    if (hEvent) {
        SetEvent(hEvent);
    }
}

// Internal close without lock
static void CloseInternal() noexcept {
    if (g_ctx.baseAddr) {
        UnmapViewOfFile(g_ctx.baseAddr);
        g_ctx.baseAddr = nullptr;
    }
    if (g_ctx.hMapFile) {
        CloseHandle(g_ctx.hMapFile);
        g_ctx.hMapFile = nullptr;
    }
    if (g_ctx.hMutex) {
        CloseHandle(g_ctx.hMutex);
        g_ctx.hMutex = nullptr;
    }
    if (g_ctx.hEvent) {
        CloseHandle(g_ctx.hEvent);
        g_ctx.hEvent = nullptr;
    }
    g_ctx.mappedSize = 0;
    g_ctx.mapName.clear();
    g_ctx.isCreator = false;
}

} // anonymous namespace

extern "C" {

SHMVAR_API int32_t ShmVar_Init(const char* mapName, size_t initialSize) {
    if (!mapName || *mapName == '\0') {
        return SHMVAR_ERR_INVALID_ARG;
    }

    // Limit maximum size to 4GB due to 32-bit offset indexing
    if (initialSize > shm::MAX_SHM_SIZE) {
        return SHMVAR_ERR_INVALID_ARG;
    }

    std::unique_lock<std::shared_mutex> guard(g_lifecycleLock);

    // If already initialized with same name, return OK
    if (g_ctx.baseAddr != nullptr && g_ctx.mapName == mapName) {
        return SHMVAR_OK;
    }

    // If already attached to a different map, safely close old resources first
    if (g_ctx.baseAddr != nullptr) {
        CloseInternal();
    }

    // Default 16MB if 0 or too small
    if (initialSize < 1024 * 1024) {
        initialSize = 16 * 1024 * 1024;
    }

    std::string shmName = std::string("Local\\ShmVar_Map_") + mapName;
    std::string mtxName = std::string("Local\\ShmVar_Mtx_") + mapName;
    std::string evtName = std::string("Local\\ShmVar_Evt_") + mapName;

    // Create / Open Mutex
    HANDLE hMutex = CreateMutexA(NULL, FALSE, mtxName.c_str());
    if (!hMutex) {
        return SHMVAR_ERR_SYS_FAIL;
    }

    // Lock mutex while initializing mapping
    CrossProcessLock lock(hMutex);
    if (!lock.isLocked()) {
        CloseHandle(hMutex);
        return SHMVAR_ERR_SYS_FAIL;
    }

    // Create / Open Event
    HANDLE hEvent = CreateEventA(NULL, FALSE, FALSE, evtName.c_str());
    if (!hEvent) {
        CloseHandle(hMutex);
        return SHMVAR_ERR_SYS_FAIL;
    }

    // Create File Mapping using INVALID_HANDLE_VALUE (pure RAM)
    DWORD sizeHigh = static_cast<DWORD>((initialSize >> 32) & 0xFFFFFFFF);
    DWORD sizeLow = static_cast<DWORD>(initialSize & 0xFFFFFFFF);

    HANDLE hMap = CreateFileMappingA(
        INVALID_HANDLE_VALUE,
        NULL,
        PAGE_READWRITE,
        sizeHigh,
        sizeLow,
        shmName.c_str()
    );

    if (hMap == NULL) {
        CloseHandle(hEvent);
        CloseHandle(hMutex);
        return SHMVAR_ERR_SYS_FAIL;
    }

    bool isCreator = (GetLastError() != ERROR_ALREADY_EXISTS);

    // Map view
    uint8_t* pBase = static_cast<uint8_t*>(MapViewOfFile(hMap, FILE_MAP_ALL_ACCESS, 0, 0, 0));
    if (!pBase) {
        CloseHandle(hMap);
        CloseHandle(hEvent);
        CloseHandle(hMutex);
        return SHMVAR_ERR_SYS_FAIL;
    }

    auto* header = reinterpret_cast<shm::ShmHeader*>(pBase);

    if (isCreator) {
        // Layout: Header at offset 0, Buddy Arena right after Header aligned to 64 bytes
        uint32_t arenaOff = static_cast<uint32_t>((sizeof(shm::ShmHeader) + 63) & ~63);
        uint32_t arenaSz = static_cast<uint32_t>(initialSize - arenaOff);

        // Format Buddy Allocator in the arena
        if (!shm::ShmBuddyAllocator::Format(pBase + arenaOff, arenaSz)) {
            UnmapViewOfFile(pBase);
            CloseHandle(hMap);
            CloseHandle(hEvent);
            CloseHandle(hMutex);
            return SHMVAR_ERR_SYS_FAIL;
        }

        header->magic = shm::SHM_MAGIC;
        header->version = shm::SHM_VERSION;
        header->totalSize = initialSize;
        header->arenaOffset = arenaOff;
        header->arenaSize = arenaSz;
        header->changeCount = 0;
        header->entryCount = 0;
        header->reserved = 0;
        for (size_t i = 0; i < shm::HASH_BUCKET_COUNT; ++i) {
            header->buckets[i] = shm::OFFSET_NIL;
        }
    } else {
        // Validate existing shared memory layout
        if (header->magic != shm::SHM_MAGIC || header->version != shm::SHM_VERSION || header->totalSize > shm::MAX_SHM_SIZE) {
            UnmapViewOfFile(pBase);
            CloseHandle(hMap);
            CloseHandle(hEvent);
            CloseHandle(hMutex);
            return SHMVAR_ERR_SYS_FAIL;
        }
    }

    // Save to g_ctx
    g_ctx.hMapFile = hMap;
    g_ctx.baseAddr = pBase;
    g_ctx.mappedSize = initialSize;
    g_ctx.hMutex = hMutex;
    g_ctx.hEvent = hEvent;
    g_ctx.mapName = mapName;
    g_ctx.isCreator = isCreator;

    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_Close(void) {
    std::unique_lock<std::shared_mutex> guard(g_lifecycleLock);
    CloseInternal();
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetInt(const char* key, int64_t val) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    int32_t rc = SetScalarValue(*header, g_ctx.baseAddr, keyView, keyHash, val);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetInt(const char* key, int64_t* outVal) {
    if (!key || !outVal) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_INT) return SHMVAR_ERR_TYPE_MISMATCH;

    *outVal = node->payload.intVal;
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetDouble(const char* key, double val) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    int32_t rc = SetScalarValue(*header, g_ctx.baseAddr, keyView, keyHash, val);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetDouble(const char* key, double* outVal) {
    if (!key || !outVal) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_DOUBLE) return SHMVAR_ERR_TYPE_MISMATCH;

    *outVal = node->payload.doubleVal;
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetStr(const char* key, const char* str) {
    if (!key || !str) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    std::string_view valView(str);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    int32_t rc = SetBlobValue(*header, g_ctx.baseAddr, keyView, keyHash, valView.data(), valView.size(), SHMVAR_TYPE_STRING, true);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetStr(const char* key, char* buf, size_t bufSize, size_t* outLen) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_STRING) return SHMVAR_ERR_TYPE_MISMATCH;

    const uint32_t dataLen = node->dataLen; // includes null terminator
    if (outLen) {
        *outLen = dataLen;
    }

    if (!buf || bufSize < dataLen) {
        return SHMVAR_ERR_BUF_TOO_SMALL;
    }

    if (dataLen > 0 && node->payload.dataOffset != shm::OFFSET_NIL) {
        const char* src = OffsetToPointer<const char>(g_ctx.baseAddr, node->payload.dataOffset);
        if (src) {
            std::memcpy(buf, src, dataLen);
        }
    }
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetBytes(const char* key, const void* data, size_t size) {
    if (!key || (!data && size > 0)) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    int32_t rc = SetBlobValue(*header, g_ctx.baseAddr, keyView, keyHash, data, size, SHMVAR_TYPE_BYTES, false);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetBytes(const char* key, void* buf, size_t bufSize, size_t* outLen) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_BYTES) return SHMVAR_ERR_TYPE_MISMATCH;

    const uint32_t dataLen = node->dataLen;
    if (outLen) {
        *outLen = dataLen;
    }

    if (!buf || bufSize < dataLen) {
        return SHMVAR_ERR_BUF_TOO_SMALL;
    }

    if (dataLen > 0 && node->payload.dataOffset != shm::OFFSET_NIL) {
        const void* src = OffsetToPointer(g_ctx.baseAddr, node->payload.dataOffset);
        if (src) {
            std::memcpy(buf, src, dataLen);
        }
    }
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_Delete(const char* key) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    uint32_t prevOffset = shm::OFFSET_NIL;
    uint32_t bucketIdx = 0;
    uint32_t nodeOffset = shm::OFFSET_NIL;
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, &prevOffset, &bucketIdx, &nodeOffset);

    if (!node) return SHMVAR_ERR_NOT_FOUND;

    // Unlink node from hash bucket list
    if (prevOffset == shm::OFFSET_NIL) {
        header->buckets[bucketIdx] = node->nextOffset;
    } else {
        auto* prevNode = OffsetToPointer<shm::ShmNode>(g_ctx.baseAddr, prevOffset);
        if (prevNode) {
            prevNode->nextOffset = node->nextOffset;
        }
    }

    if (header->entryCount > 0) {
        header->entryCount--;
    }

    // Free all associated memory blocks back to Buddy Allocator
    auto allocator = MakeAllocator(*header, g_ctx.baseAddr);
    if (allocator.IsValid()) {
        // 1. Free blob data payload if string or bytes
        if ((node->type == SHMVAR_TYPE_STRING || node->type == SHMVAR_TYPE_BYTES) &&
            node->payload.dataOffset != shm::OFFSET_NIL) {
            allocator.Free(node->payload.dataOffset);
        }

        // 2. Free key buffer
        if (node->keyOffset != shm::OFFSET_NIL) {
            allocator.Free(node->keyOffset);
        }

        // 3. Free node struct itself
        if (nodeOffset != shm::OFFSET_NIL) {
            allocator.Free(nodeOffset);
        }
    }

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_WaitForChange(uint32_t timeoutMs) {
    HANDLE hEvt = nullptr;
    {
        std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
        if (!g_ctx.hEvent) return SHMVAR_ERR_NOT_INIT;
        hEvt = g_ctx.hEvent;
    }

    DWORD res = WaitForSingleObject(hEvt, timeoutMs);
    if (res == WAIT_OBJECT_0) {
        return SHMVAR_OK;
    } else if (res == WAIT_TIMEOUT) {
        return SHMVAR_TIMEOUT;
    }
    return SHMVAR_ERR_SYS_FAIL;
}

SHMVAR_API int32_t ShmVar_GetType(const char* key, int32_t* outType, size_t* outSize) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;

    std::shared_lock<std::shared_mutex> lifecycleGuard(g_lifecycleLock);
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;

    if (outType) *outType = node->type;
    if (outSize) *outSize = node->dataLen;

    return SHMVAR_OK;
}

} // extern "C"
