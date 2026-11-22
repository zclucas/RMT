#define SHMVAR_EXPORTS
#include "shm_var.h"
#include "shm_internal.h"

#include <string>
#include <string_view>
#include <format>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <iostream>

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

// Thread-local or process-global context
static ShmContext g_ctx;
static std::mutex g_localLock;

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

// Helper: allocate relative offset in shared memory
uint32_t AllocateOffset(shm::ShmHeader* header, size_t size) {
    size_t aligned = shm::Align8(size);
    uint64_t current = header->freeOffset;
    if (current + aligned > header->totalSize) {
        return shm::OFFSET_NIL; // Out of memory
    }
    header->freeOffset += aligned;
    return static_cast<uint32_t>(current);
}

// Convert relative offset to pointer in current process address space
template <typename T = void>
inline T* OffsetToPointer(uint8_t* base, uint32_t offset) noexcept {
    if (offset == shm::OFFSET_NIL) return nullptr;
    return reinterpret_cast<T*>(base + offset);
}

// Notify change via Win32 Event & atomic counter
void NotifyChange(shm::ShmHeader* header, HANDLE hEvent) {
    if (header) {
        header->changeCount++;
    }
    if (hEvent) {
        PulseEvent(hEvent);
        SetEvent(hEvent);
    }
}

} // anonymous namespace

extern "C" {

SHMVAR_API int32_t ShmVar_Init(const char* mapName, size_t initialSize) {
    if (!mapName || *mapName == '\0') {
        return SHMVAR_ERR_INVALID_ARG;
    }

    std::lock_guard<std::mutex> guard(g_localLock);

    // If already initialized with same name, return OK
    if (g_ctx.baseAddr != nullptr && g_ctx.mapName == mapName) {
        return SHMVAR_OK;
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

    // Create / Open Event (Auto-reset event for broadcast)
    HANDLE hEvent = CreateEventA(NULL, FALSE, FALSE, evtName.c_str());

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

    bool isCreator = false;
    if (hMap == NULL) {
        CloseHandle(hMutex);
        if (hEvent) CloseHandle(hEvent);
        return SHMVAR_ERR_SYS_FAIL;
    }

    if (GetLastError() != ERROR_ALREADY_EXISTS) {
        isCreator = true;
    }

    // Map view
    uint8_t* pBase = static_cast<uint8_t*>(MapViewOfFile(hMap, FILE_MAP_ALL_ACCESS, 0, 0, 0));
    if (!pBase) {
        CloseHandle(hMap);
        CloseHandle(hMutex);
        if (hEvent) CloseHandle(hEvent);
        return SHMVAR_ERR_SYS_FAIL;
    }

    auto* header = reinterpret_cast<shm::ShmHeader*>(pBase);

    if (isCreator || header->magic != shm::SHM_MAGIC) {
        // Initialize header
        header->magic = shm::SHM_MAGIC;
        header->version = shm::SHM_VERSION;
        header->totalSize = initialSize;
        header->freeOffset = shm::Align8(sizeof(shm::ShmHeader));
        header->changeCount = 0;
        header->entryCount = 0;
        header->reserved = 0;
        for (size_t i = 0; i < shm::HASH_BUCKET_COUNT; ++i) {
            header->buckets[i] = shm::OFFSET_NIL;
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
    std::lock_guard<std::mutex> guard(g_localLock);

    if (!g_ctx.baseAddr) {
        return SHMVAR_OK;
    }

    UnmapViewOfFile(g_ctx.baseAddr);
    if (g_ctx.hMapFile) CloseHandle(g_ctx.hMapFile);
    if (g_ctx.hMutex) CloseHandle(g_ctx.hMutex);
    if (g_ctx.hEvent) CloseHandle(g_ctx.hEvent);

    g_ctx.hMapFile = nullptr;
    g_ctx.baseAddr = nullptr;
    g_ctx.mappedSize = 0;
    g_ctx.hMutex = nullptr;
    g_ctx.hEvent = nullptr;
    g_ctx.mapName.clear();

    return SHMVAR_OK;
}

static shm::ShmNode* FindNode(uint8_t* base, shm::ShmHeader* header, std::string_view key, uint32_t* outPrevOffset, uint32_t* outBucketIdx) {
    uint32_t bucket = shm::HashKey(key) % shm::HASH_BUCKET_COUNT;
    if (outBucketIdx) *outBucketIdx = bucket;

    uint32_t prev = shm::OFFSET_NIL;
    uint32_t curr = header->buckets[bucket];

    while (curr != shm::OFFSET_NIL) {
        auto* node = OffsetToPointer<shm::ShmNode>(base, curr);
        if (node->keyLen == key.size()) {
            const char* keyPtr = OffsetToPointer<const char>(base, node->keyOffset);
            if (keyPtr && key == std::string_view(keyPtr, node->keyLen)) {
                if (outPrevOffset) *outPrevOffset = prev;
                return node;
            }
        }
        prev = curr;
        curr = node->nextOffset;
    }

    if (outPrevOffset) *outPrevOffset = prev;
    return nullptr;
}

SHMVAR_API int32_t ShmVar_SetInt(const char* key, int64_t val) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    uint32_t prevOffset = shm::OFFSET_NIL;
    uint32_t bucketIdx = 0;
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, &prevOffset, &bucketIdx);

    if (node) {
        node->type = SHMVAR_TYPE_INT;
        node->intVal = val;
    } else {
        // Allocate node and key
        uint32_t nodeOff = AllocateOffset(header, sizeof(shm::ShmNode));
        if (nodeOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        uint32_t keyOff = AllocateOffset(header, keyView.size() + 1);
        if (keyOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        char* keyDst = OffsetToPointer<char>(g_ctx.baseAddr, keyOff);
        std::memcpy(keyDst, keyView.data(), keyView.size());
        keyDst[keyView.size()] = '\0';

        node = OffsetToPointer<shm::ShmNode>(g_ctx.baseAddr, nodeOff);
        node->nextOffset = header->buckets[bucketIdx];
        node->type = SHMVAR_TYPE_INT;
        node->keyLen = static_cast<uint32_t>(keyView.size());
        node->dataLen = sizeof(int64_t);
        node->intVal = val;
        node->doubleVal = 0.0;
        node->dataOffset = shm::OFFSET_NIL;
        node->keyOffset = keyOff;

        header->buckets[bucketIdx] = nodeOff;
        header->entryCount++;
    }

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetInt(const char* key, int64_t* outVal) {
    if (!key || !outVal) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_INT) return SHMVAR_ERR_TYPE_MISMATCH;

    *outVal = node->intVal;
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetDouble(const char* key, double val) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    uint32_t prevOffset = shm::OFFSET_NIL;
    uint32_t bucketIdx = 0;
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, &prevOffset, &bucketIdx);

    if (node) {
        node->type = SHMVAR_TYPE_DOUBLE;
        node->doubleVal = val;
    } else {
        uint32_t nodeOff = AllocateOffset(header, sizeof(shm::ShmNode));
        if (nodeOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        uint32_t keyOff = AllocateOffset(header, keyView.size() + 1);
        if (keyOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        char* keyDst = OffsetToPointer<char>(g_ctx.baseAddr, keyOff);
        std::memcpy(keyDst, keyView.data(), keyView.size());
        keyDst[keyView.size()] = '\0';

        node = OffsetToPointer<shm::ShmNode>(g_ctx.baseAddr, nodeOff);
        node->nextOffset = header->buckets[bucketIdx];
        node->type = SHMVAR_TYPE_DOUBLE;
        node->keyLen = static_cast<uint32_t>(keyView.size());
        node->dataLen = sizeof(double);
        node->intVal = 0;
        node->doubleVal = val;
        node->dataOffset = shm::OFFSET_NIL;
        node->keyOffset = keyOff;

        header->buckets[bucketIdx] = nodeOff;
        header->entryCount++;
    }

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetDouble(const char* key, double* outVal) {
    if (!key || !outVal) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_DOUBLE) return SHMVAR_ERR_TYPE_MISMATCH;

    *outVal = node->doubleVal;
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetStr(const char* key, const char* str) {
    if (!key || !str) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    std::string_view valView(str);
    size_t reqLen = valView.size() + 1; // Include null terminator

    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    uint32_t prevOffset = shm::OFFSET_NIL;
    uint32_t bucketIdx = 0;
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, &prevOffset, &bucketIdx);

    if (node) {
        // Reuse buffer if capacity allows, otherwise reallocate
        if (node->dataOffset == shm::OFFSET_NIL || node->dataLen < reqLen) {
            uint32_t dataOff = AllocateOffset(header, reqLen);
            if (dataOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;
            node->dataOffset = dataOff;
        }
        char* dst = OffsetToPointer<char>(g_ctx.baseAddr, node->dataOffset);
        std::memcpy(dst, valView.data(), valView.size());
        dst[valView.size()] = '\0';
        node->type = SHMVAR_TYPE_STRING;
        node->dataLen = static_cast<uint32_t>(reqLen);
    } else {
        uint32_t nodeOff = AllocateOffset(header, sizeof(shm::ShmNode));
        if (nodeOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        uint32_t keyOff = AllocateOffset(header, keyView.size() + 1);
        if (keyOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        char* keyDst = OffsetToPointer<char>(g_ctx.baseAddr, keyOff);
        std::memcpy(keyDst, keyView.data(), keyView.size());
        keyDst[keyView.size()] = '\0';

        uint32_t dataOff = AllocateOffset(header, reqLen);
        if (dataOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        char* dst = OffsetToPointer<char>(g_ctx.baseAddr, dataOff);
        std::memcpy(dst, valView.data(), valView.size());
        dst[valView.size()] = '\0';

        node = OffsetToPointer<shm::ShmNode>(g_ctx.baseAddr, nodeOff);
        node->nextOffset = header->buckets[bucketIdx];
        node->type = SHMVAR_TYPE_STRING;
        node->keyLen = static_cast<uint32_t>(keyView.size());
        node->dataLen = static_cast<uint32_t>(reqLen);
        node->intVal = 0;
        node->doubleVal = 0.0;
        node->dataOffset = dataOff;
        node->keyOffset = keyOff;

        header->buckets[bucketIdx] = nodeOff;
        header->entryCount++;
    }

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetStr(const char* key, char* buf, size_t bufSize, size_t* outLen) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_STRING) return SHMVAR_ERR_TYPE_MISMATCH;

    if (outLen) {
        *outLen = node->dataLen; // includes null terminator
    }

    if (!buf || bufSize < node->dataLen) {
        return SHMVAR_ERR_BUF_TOO_SMALL;
    }

    const char* src = OffsetToPointer<const char>(g_ctx.baseAddr, node->dataOffset);
    if (src) {
        std::memcpy(buf, src, node->dataLen);
    }
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetBytes(const char* key, const void* data, size_t size) {
    if (!key || (!data && size > 0)) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    uint32_t prevOffset = shm::OFFSET_NIL;
    uint32_t bucketIdx = 0;
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, &prevOffset, &bucketIdx);

    if (node) {
        if (node->dataOffset == shm::OFFSET_NIL || node->dataLen < size) {
            uint32_t dataOff = AllocateOffset(header, size);
            if (size > 0 && dataOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;
            node->dataOffset = dataOff;
        }
        if (size > 0 && data) {
            void* dst = OffsetToPointer(g_ctx.baseAddr, node->dataOffset);
            std::memcpy(dst, data, size);
        }
        node->type = SHMVAR_TYPE_BYTES;
        node->dataLen = static_cast<uint32_t>(size);
    } else {
        uint32_t nodeOff = AllocateOffset(header, sizeof(shm::ShmNode));
        if (nodeOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        uint32_t keyOff = AllocateOffset(header, keyView.size() + 1);
        if (keyOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;

        char* keyDst = OffsetToPointer<char>(g_ctx.baseAddr, keyOff);
        std::memcpy(keyDst, keyView.data(), keyView.size());
        keyDst[keyView.size()] = '\0';

        uint32_t dataOff = shm::OFFSET_NIL;
        if (size > 0) {
            dataOff = AllocateOffset(header, size);
            if (dataOff == shm::OFFSET_NIL) return SHMVAR_ERR_NO_MEM;
            void* dst = OffsetToPointer(g_ctx.baseAddr, dataOff);
            std::memcpy(dst, data, size);
        }

        node = OffsetToPointer<shm::ShmNode>(g_ctx.baseAddr, nodeOff);
        node->nextOffset = header->buckets[bucketIdx];
        node->type = SHMVAR_TYPE_BYTES;
        node->keyLen = static_cast<uint32_t>(keyView.size());
        node->dataLen = static_cast<uint32_t>(size);
        node->intVal = 0;
        node->doubleVal = 0.0;
        node->dataOffset = dataOff;
        node->keyOffset = keyOff;

        header->buckets[bucketIdx] = nodeOff;
        header->entryCount++;
    }

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetBytes(const char* key, void* buf, size_t bufSize, size_t* outLen) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_BYTES) return SHMVAR_ERR_TYPE_MISMATCH;

    if (outLen) {
        *outLen = node->dataLen;
    }

    if (!buf || bufSize < node->dataLen) {
        return SHMVAR_ERR_BUF_TOO_SMALL;
    }

    if (node->dataLen > 0 && node->dataOffset != shm::OFFSET_NIL) {
        const void* src = OffsetToPointer(g_ctx.baseAddr, node->dataOffset);
        if (src) {
            std::memcpy(buf, src, node->dataLen);
        }
    }
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_Delete(const char* key) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    uint32_t prevOffset = shm::OFFSET_NIL;
    uint32_t bucketIdx = 0;
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, &prevOffset, &bucketIdx);

    if (!node) return SHMVAR_ERR_NOT_FOUND;

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

    NotifyChange(header, g_ctx.hEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_WaitForChange(uint32_t timeoutMs) {
    if (!g_ctx.hEvent) return SHMVAR_ERR_NOT_INIT;

    DWORD res = WaitForSingleObject(g_ctx.hEvent, timeoutMs);
    if (res == WAIT_OBJECT_0) {
        return SHMVAR_OK;
    } else if (res == WAIT_TIMEOUT) {
        return SHMVAR_TIMEOUT;
    }
    return SHMVAR_ERR_SYS_FAIL;
}

SHMVAR_API int32_t ShmVar_GetType(const char* key, int32_t* outType, size_t* outSize) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    CrossProcessLock lock(g_ctx.hMutex);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    auto* node = FindNode(g_ctx.baseAddr, header, keyView, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;

    if (outType) *outType = node->type;
    if (outSize) *outSize = node->dataLen;

    return SHMVAR_OK;
}

} // extern "C"
