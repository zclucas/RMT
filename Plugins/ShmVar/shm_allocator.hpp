#pragma once

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <span>
#include <optional>
#include "buddy_alloc.hpp"

namespace shm {

// Process-local adapter around modern C++23 buddy::allocator embedded in shared memory.
// Does NOT store persistent pointers in shared memory.
// All allocation & free interfaces operate strictly on relative uint32_t offsets.
class ShmBuddyAllocator {
public:
    static constexpr size_t DEFAULT_ALIGNMENT = 64; // Default minimum block size of C++23 buddy allocator

    // Formats and initializes buddy metadata embedded in the arena. Called only by mapping Creator.
    static bool Format(uint8_t* arenaBase, size_t arenaSize) noexcept {
        if (!arenaBase || arenaSize == 0) return false;
        auto arenaSpan = std::span<std::byte>(reinterpret_cast<std::byte*>(arenaBase), arenaSize);
        auto result = buddy::allocator::create_embedded(arenaSpan, buddy::allocator::npos, DEFAULT_ALIGNMENT);
        return result.has_value();
    }

    // Creates an in-process local adapter bound to the given base and arena.
    // Works across different processes regardless of where arenaBase is mapped.
    explicit ShmBuddyAllocator(uint8_t* base, uint32_t arenaOffset, size_t arenaSize) noexcept
        : base_(base), arenaBase_(base + arenaOffset), arenaOffset_(arenaOffset), arenaSize_(arenaSize) {
        if (arenaBase_ && arenaSize_ > 0) {
            auto arenaSpan = std::span<std::byte>(reinterpret_cast<std::byte*>(arenaBase_), arenaSize_);
            auto attached = buddy::allocator::attach_embedded(arenaSpan, DEFAULT_ALIGNMENT);
            if (attached) {
                allocator_.emplace(std::move(*attached));
            }
        }
    }

    bool IsValid() const noexcept {
        return (base_ != nullptr && allocator_.has_value());
    }

    // Allocate memory from arena and return relative offset to mapping base
    uint32_t Allocate(size_t size) noexcept {
        if (!allocator_ || size == 0) return 0xFFFFFFFF; // OFFSET_NIL

        auto blockRes = allocator_->allocate(size);
        if (!blockRes) return 0xFFFFFFFF; // OFFSET_NIL

        auto* pByte = reinterpret_cast<uint8_t*>(blockRes->data());
        return static_cast<uint32_t>(pByte - base_);
    }

    // Free memory back to buddy allocator using relative offset to mapping base
    void Free(uint32_t offset) noexcept {
        if (!allocator_ || offset == 0xFFFFFFFF) return;

        uint8_t* pByte = base_ + offset;
        auto* bytePtr = reinterpret_cast<std::byte*>(pByte);

        auto sizeRes = allocator_->allocation_size(bytePtr);
        if (!sizeRes) return;

        auto blockSpan = std::span<std::byte>(bytePtr, *sizeRes);
        (void)allocator_->deallocate(blockSpan);
    }

    // Return current allocation slot size for an offset
    size_t GetAllocSize(uint32_t offset) noexcept {
        if (!allocator_ || offset == 0xFFFFFFFF) return 0;
        uint8_t* pByte = base_ + offset;
        auto* bytePtr = reinterpret_cast<std::byte*>(pByte);
        auto sizeRes = allocator_->allocation_size(bytePtr);
        return sizeRes.value_or(0);
    }

private:
    uint8_t* base_{nullptr};
    uint8_t* arenaBase_{nullptr};
    uint32_t arenaOffset_{0};
    size_t arenaSize_{0};
    std::optional<buddy::allocator> allocator_;
};

} // namespace shm
