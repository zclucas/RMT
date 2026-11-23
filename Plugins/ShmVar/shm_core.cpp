#ifndef SHMVAR_EXPORTS
#define SHMVAR_EXPORTS
#endif

#define BUDDY_ALLOC_IMPLEMENTATION
#include "shm_core.h"

namespace shm {

// Global in-process context & lifecycle lock definitions
ShmContext g_ctx;
std::mutex g_lifecycleLock;

// Find existing node or bucket insertion point
ShmNode* FindNode(uint8_t* base, ShmHeader* header, std::string_view key, uint32_t keyHash, uint32_t* outPrevOffset, uint32_t* outBucketIdx, uint32_t* outNodeOffset) noexcept {
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
ShmNode* GetOrCreateNode(ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash) noexcept {
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

// Common blob write logic with in-place overwrite & safe allocate-switch-free order
int32_t SetBlobValue(ShmHeader& header, uint8_t* base, std::string_view key, uint32_t keyHash, const void* data, size_t size, uint32_t type, bool nullTerminate) noexcept {
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

// Internal close without lock
void CloseInternal() noexcept {
    if (g_ctx.baseAddr) {
        UnmapViewOfFile(g_ctx.baseAddr);
        g_ctx.baseAddr = nullptr;
    }
    if (g_ctx.hMapFile) {
        CloseHandle(g_ctx.hMapFile);
        g_ctx.hMapFile = nullptr;
    }
    if (g_ctx.sync.hWriterMutex) {
        CloseHandle(g_ctx.sync.hWriterMutex);
        g_ctx.sync.hWriterMutex = nullptr;
    }
    if (g_ctx.sync.hNoReadersEvent) {
        CloseHandle(g_ctx.sync.hNoReadersEvent);
        g_ctx.sync.hNoReadersEvent = nullptr;
    }
    if (g_ctx.sync.hNotifyEvent) {
        CloseHandle(g_ctx.sync.hNotifyEvent);
        g_ctx.sync.hNotifyEvent = nullptr;
    }
    g_ctx.mappedSize = 0;
    g_ctx.mapName.clear();
    g_ctx.isCreator = false;
}

} // namespace shm
