#ifndef SHM_CORE_H
#define SHM_CORE_H

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
#include <windows.h>

namespace shm {

// Process-local context structure
struct ShmContext {
    HANDLE hMapFile = nullptr;
    uint8_t* baseAddr = nullptr;
    size_t mappedSize = 0;
    HANDLE hMutex = nullptr;
    HANDLE hEvent = nullptr;
    std::string mapName;
    bool isCreator = false;
};

// Global in-process context & lifecycle lock declarations
extern ShmContext g_ctx;
extern std::shared_mutex g_lifecycleLock;

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
ShmNode* FindNode(uint8_t* base, ShmHeader* header, std::string_view key, uint32_t keyHash, uint32_t* outPrevOffset, uint32_t* outBucketIdx, uint32_t* outNodeOffset = nullptr) noexcept;

// Find or allocate a new ShmNode and key buffer via Buddy Allocator
ShmNode* GetOrCreateNode(ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash) noexcept;

// Template helper to set scalar values (int64_t or double)
template <typename T>
int32_t SetScalarValue(ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash, T val) noexcept {
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
int32_t SetBlobValue(ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash, const void* data, size_t size, uint32_t type, bool nullTerminate) noexcept;

// Reliable notification via event signaling
inline void NotifyChange(ShmHeader* header, HANDLE hEvent) noexcept {
    if (header) {
        header->changeCount++;
    }
    if (hEvent) {
        SetEvent(hEvent);
    }
}

// Internal close without lock
void CloseInternal() noexcept;

} // namespace shm

#endif // SHM_CORE_H
