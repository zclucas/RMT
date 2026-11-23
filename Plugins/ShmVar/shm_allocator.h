#ifndef SHM_ALLOCATOR_H
#define SHM_ALLOCATOR_H

#include <cstdint>
#include <cstddef>
#include <cstring>
#include "buddy_alloc.h"

namespace shm {

// Process-local adapter around buddy_alloc embedded in shared memory.
// Does NOT store persistent pointers in shared memory.
// All allocation & free interfaces operate strictly on relative uint32_t offsets.
class ShmBuddyAllocator {
public:
    static constexpr size_t DEFAULT_ALIGNMENT = 16; // 16 bytes alignment: great for ShmNode (32B) & 8-byte aligned types

    // Formats and initializes buddy metadata embedded in the arena. Called only by mapping Creator.
    static bool Format(uint8_t* arenaBase, size_t arenaSize) noexcept {
        if (!arenaBase || arenaSize == 0) return false;
        struct buddy* b = buddy_embed_alignment(arenaBase, arenaSize, DEFAULT_ALIGNMENT);
        return (b != nullptr);
    }

    // Creates an in-process local adapter bound to the given base and arena.
    // Works across different processes regardless of where arenaBase is mapped.
    explicit ShmBuddyAllocator(uint8_t* base, uint32_t arenaOffset, size_t arenaSize) noexcept
        : base_(base), arenaBase_(base + arenaOffset), arenaOffset_(arenaOffset), arenaSize_(arenaSize) {
        buddy_ = buddy_get_embed_at_alignment(arenaBase_, arenaSize_, DEFAULT_ALIGNMENT);
    }

    bool IsValid() const noexcept {
        return (base_ != nullptr && buddy_ != nullptr);
    }

    // Allocate memory from arena and return relative offset to mapping base
    uint32_t Allocate(size_t size) noexcept {
        if (!buddy_ || size == 0) return 0xFFFFFFFF; // OFFSET_NIL

        void* ptr = buddy_malloc(buddy_, size);
        if (!ptr) return 0xFFFFFFFF; // OFFSET_NIL

        uint8_t* pByte = static_cast<uint8_t*>(ptr);
        return static_cast<uint32_t>(pByte - base_);
    }

    // Free memory back to buddy allocator using relative offset to mapping base
    void Free(uint32_t offset) noexcept {
        if (!buddy_ || offset == 0xFFFFFFFF) return;

        void* ptr = base_ + offset;
        buddy_free(buddy_, ptr);
    }

    // Return current allocation slot size for an offset
    size_t GetAllocSize(uint32_t offset) noexcept {
        if (!buddy_ || offset == 0xFFFFFFFF) return 0;
        void* ptr = base_ + offset;
        return buddy_alloc_size(buddy_, ptr);
    }

private:
    uint8_t* base_;
    uint8_t* arenaBase_;
    uint32_t arenaOffset_;
    size_t arenaSize_;
    struct buddy* buddy_;
};

} // namespace shm

#endif // SHM_ALLOCATOR_H
