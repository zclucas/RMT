#ifndef SHMVAR_EXPORTS
#define SHMVAR_EXPORTS
#endif

#include "shm_var.h"
#include "shm_core.hpp"

using namespace shm;

extern "C" {

SHMVAR_API int32_t ShmVar_Init(const char* mapName, size_t initialSize) {
    if (!mapName || *mapName == '\0') {
        return SHMVAR_ERR_INVALID_ARG;
    }

    std::lock_guard<std::mutex> guard(g_lifecycleLock);

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
    std::string nrEvtName = std::string("Local\\ShmVar_NREvt_") + mapName;
    std::string ntfEvtName = std::string("Local\\ShmVar_Evt_") + mapName;

    // Create / Open Writer Mutex
    HANDLE hWriterMutex = CreateMutexA(NULL, FALSE, mtxName.c_str());
    if (!hWriterMutex) {
        return SHMVAR_ERR_SYS_FAIL;
    }

    // Create / Open NoReaders Event (Manual-reset, initially signaled when created)
    HANDLE hNoReadersEvent = CreateEventA(NULL, TRUE, TRUE, nrEvtName.c_str());
    if (!hNoReadersEvent) {
        CloseHandle(hWriterMutex);
        return SHMVAR_ERR_SYS_FAIL;
    }

    // Create / Open Notify Event (Auto-reset event for change broadcast)
    HANDLE hNotifyEvent = CreateEventA(NULL, FALSE, FALSE, ntfEvtName.c_str());
    if (!hNotifyEvent) {
        CloseHandle(hNoReadersEvent);
        CloseHandle(hWriterMutex);
        return SHMVAR_ERR_SYS_FAIL;
    }

    // Create File Mapping using INVALID_HANDLE_VALUE (pure RAM)
    DWORD sizeHigh = static_cast<DWORD>((static_cast<uint64_t>(initialSize) >> 32) & 0xFFFFFFFF);
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
        CloseHandle(hNotifyEvent);
        CloseHandle(hNoReadersEvent);
        CloseHandle(hWriterMutex);
        return SHMVAR_ERR_SYS_FAIL;
    }

    bool isCreator = (GetLastError() != ERROR_ALREADY_EXISTS);

    // Map view
    uint8_t* pBase = static_cast<uint8_t*>(MapViewOfFile(hMap, FILE_MAP_ALL_ACCESS, 0, 0, 0));
    if (!pBase) {
        CloseHandle(hMap);
        CloseHandle(hNotifyEvent);
        CloseHandle(hNoReadersEvent);
        CloseHandle(hWriterMutex);
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
            CloseHandle(hNotifyEvent);
            CloseHandle(hNoReadersEvent);
            CloseHandle(hWriterMutex);
            return SHMVAR_ERR_SYS_FAIL;
        }

        header->magic = shm::SHM_MAGIC;
        header->totalSize = initialSize;
        header->arenaOffset = arenaOff;
        header->arenaSize = arenaSz;
        header->changeCount = 0;
        header->entryCount = 0;
        header->readerCount.store(0, std::memory_order_relaxed);
        header->writerWaiting.store(0, std::memory_order_relaxed);
        header->reserved = 0;
        for (size_t i = 0; i < shm::HASH_BUCKET_COUNT; ++i) {
            header->buckets[i] = shm::OFFSET_NIL;
        }
        SetEvent(hNoReadersEvent); // Initially no readers
    } else {
        // Validate existing shared memory layout
        if (header->magic != shm::SHM_MAGIC) {
            UnmapViewOfFile(pBase);
            CloseHandle(hMap);
            CloseHandle(hNotifyEvent);
            CloseHandle(hNoReadersEvent);
            CloseHandle(hWriterMutex);
            return SHMVAR_ERR_SYS_FAIL;
        }
    }

    // Save to g_ctx
    g_ctx.hMapFile = hMap;
    g_ctx.baseAddr = pBase;
    g_ctx.mappedSize = initialSize;
    g_ctx.sync.hWriterMutex = hWriterMutex;
    g_ctx.sync.hNoReadersEvent = hNoReadersEvent;
    g_ctx.sync.hNotifyEvent = hNotifyEvent;
    g_ctx.mapName = mapName;
    g_ctx.isCreator = isCreator;

    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_Close(void) {
    std::lock_guard<std::mutex> guard(g_lifecycleLock);
    CloseInternal();
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetInt(const char* key, int64_t val) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessExclusiveLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    int32_t rc = SetScalarValue(*header, g_ctx.baseAddr, keyView, keyHash, val);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.sync.hNotifyEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetInt(const char* key, int64_t* outVal) {
    if (!key || !outVal) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessSharedLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_INT) return SHMVAR_ERR_TYPE_MISMATCH;

    *outVal = node->payload.intVal;
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetDouble(const char* key, double val) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessExclusiveLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    int32_t rc = SetScalarValue(*header, g_ctx.baseAddr, keyView, keyHash, val);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.sync.hNotifyEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetDouble(const char* key, double* outVal) {
    if (!key || !outVal) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessSharedLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;
    if (node->type != SHMVAR_TYPE_DOUBLE) return SHMVAR_ERR_TYPE_MISMATCH;

    *outVal = node->payload.doubleVal;
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_SetStr(const char* key, const char* str) {
    if (!key || !str) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    std::string_view valView(str);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessExclusiveLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    int32_t rc = SetBlobValue(*header, g_ctx.baseAddr, keyView, keyHash, valView.data(), valView.size(), SHMVAR_TYPE_STRING, true);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.sync.hNotifyEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetStr(const char* key, char* buf, size_t bufSize, size_t* outLen) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessSharedLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

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
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessExclusiveLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    int32_t rc = SetBlobValue(*header, g_ctx.baseAddr, keyView, keyHash, data, size, SHMVAR_TYPE_BYTES, false);
    if (rc != SHMVAR_OK) return rc;

    NotifyChange(header, g_ctx.sync.hNotifyEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetBytes(const char* key, void* buf, size_t bufSize, size_t* outLen) {
    if (!key) return SHMVAR_ERR_INVALID_ARG;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessSharedLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

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
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessExclusiveLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

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

    NotifyChange(header, g_ctx.sync.hNotifyEvent);
    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_WaitForChange(uint32_t timeoutMs) {
    HANDLE hEvt = nullptr;
    {
        std::lock_guard<std::mutex> guard(g_lifecycleLock);
        if (!g_ctx.sync.hNotifyEvent) return SHMVAR_ERR_NOT_INIT;
        hEvt = g_ctx.sync.hNotifyEvent;
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
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    std::string_view keyView(key);
    uint32_t keyHash = shm::HashKey(keyView);

    auto* header = reinterpret_cast<shm::ShmHeader*>(g_ctx.baseAddr);
    CrossProcessSharedLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    auto* node = FindNode(g_ctx.baseAddr, header, keyView, keyHash, nullptr, nullptr);

    if (!node) return SHMVAR_ERR_NOT_FOUND;

    if (outType) *outType = node->type;
    if (outSize) *outSize = node->dataLen;

    return SHMVAR_OK;
}

SHMVAR_API int32_t ShmVar_GetKeys(char* buf, size_t bufSize, size_t* outLen) {
    if (!outLen || (!buf && bufSize != 0)) return SHMVAR_ERR_INVALID_ARG;
    *outLen = 0;
    if (!g_ctx.baseAddr) return SHMVAR_ERR_NOT_INIT;

    auto* header = reinterpret_cast<ShmHeader*>(g_ctx.baseAddr);
    CrossProcessSharedLock lock(header, g_ctx.sync);
    if (!lock.isLocked()) return SHMVAR_ERR_SYS_FAIL;

    // Read length and copy under the same shared lock. Each UTF-8 key includes NUL.
    size_t required = 0;
    for (auto offset : header->buckets) {
        while (offset != OFFSET_NIL) {
            auto* node = OffsetToPointer<ShmNode>(g_ctx.baseAddr, offset);
            required += static_cast<size_t>(node->keyLen) + 1;
            offset = node->nextOffset;
        }
    }
    *outLen = required;
    if (required == 0) return SHMVAR_OK;
    if (!buf || bufSize < required) return SHMVAR_ERR_BUF_TOO_SMALL;

    size_t written = 0;
    for (auto offset : header->buckets) {
        while (offset != OFFSET_NIL) {
            auto* node = OffsetToPointer<ShmNode>(g_ctx.baseAddr, offset);
            const auto* key = OffsetToPointer<const char>(g_ctx.baseAddr, node->keyOffset);
            std::memcpy(buf + written, key, node->keyLen);
            written += node->keyLen;
            buf[written++] = '\0';
            offset = node->nextOffset;
        }
    }
    return SHMVAR_OK;
}

} // extern "C"
