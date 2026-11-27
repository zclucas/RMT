/**
 * @author 火焰
 * @brief 這是一個使用 C++ 實現的 binary buddy 記憶體配置器
 * @date 2026-11-24
 */

#pragma once

#include <algorithm>
#include <bit>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <expected>
#include <functional>
#include <limits>
#include <memory>
#include <span>
#include <utility>

namespace buddy {

enum class error : std::uint8_t {
    invalid_arena,
    invalid_metadata,
    metadata_overlap,
    invalid_alignment,
    invalid_size,
    out_of_memory,
    invalid_block,
    size_mismatch,
    range_conflict,
    not_reserved,
    resize_out_of_range,
    allocations_outside_new_size,
    allocator_moved_from,
    corrupted_metadata,
};

enum class reallocation_mode : std::uint8_t {
    preserve_contents,
    discard_contents,
};

enum class block_kind : std::uint8_t {
    free,
    allocated,
    reserved,
};

/** Describes one maximal free, allocated, or reserved interval returned by walk(). */
struct block_info {
    std::span<std::byte> memory;
    block_kind kind;
};

/**
 * A non-owning, move-only C++23 binary buddy allocator.
 *
 * The default minimum allocation unit is 64 bytes. Both the arena and the
 * metadata storage are supplied by the caller; no global heap allocation is
 * performed. create_embedded() stores metadata at the end of the supplied
 * arena, while create() accepts a separate metadata span.
 *
 * All returned spans describe the complete buddy block, not merely the
 * requested byte count. The backing arena and metadata must outlive this
 * allocator. This type is not thread-safe.
 */
class allocator final {
public:
    using size_type = std::size_t;
    using block_type = std::span<std::byte>;

    static constexpr size_type default_minimum_block_size = 64;
    static constexpr size_type npos = std::numeric_limits<size_type>::max();

    allocator(const allocator&) = delete;
    allocator& operator=(const allocator&) = delete;

    allocator(allocator&& other) noexcept { move_from(other); }

    allocator& operator=(allocator&& other) noexcept {
        if (this != &other) {
            move_from(other);
        }
        return *this;
    }

    /**
     * Returns the required metadata size for an arena of maximum_arena_size.
     * The arena size is rounded down to a whole number of minimum blocks.
     */
    [[nodiscard]] static std::expected<size_type, error>
    required_metadata_size(
        size_type maximum_arena_size,
        size_type minimum_block_size = default_minimum_block_size) noexcept {
        const auto layout = make_layout(maximum_arena_size, minimum_block_size);
        if (!layout) {
            return std::unexpected(layout.error());
        }
        return layout->metadata_size;
    }

    /**
     * Creates an allocator whose metadata lives in a separate caller-owned
     * buffer. initial_size defaults to the full arena span.
     */
    [[nodiscard]] static std::expected<allocator, error>
    create(block_type arena,
           std::span<std::byte> metadata,
           size_type initial_size = npos,
           size_type minimum_block_size = default_minimum_block_size) noexcept {
        if (arena.empty() || arena.data() == nullptr) {
            return std::unexpected(error::invalid_arena);
        }
        if (!valid_minimum_block_size(minimum_block_size)) {
            return std::unexpected(error::invalid_alignment);
        }
        if (reinterpret_cast<std::uintptr_t>(arena.data()) % minimum_block_size != 0) {
            return std::unexpected(error::invalid_alignment);
        }

        const auto layout = make_layout(arena.size(), minimum_block_size);
        if (!layout) {
            return std::unexpected(layout.error());
        }
        if (metadata.empty() || metadata.data() == nullptr ||
            reinterpret_cast<std::uintptr_t>(metadata.data()) % alignof(metadata_header) != 0 ||
            metadata.size() < layout->metadata_size) {
            return std::unexpected(error::invalid_metadata);
        }
        if (ranges_overlap(arena, metadata)) {
            return std::unexpected(error::metadata_overlap);
        }

        const size_type active_size = initial_size == npos
            ? layout->maximum_capacity
            : align_down(initial_size, minimum_block_size);
        if (active_size == 0 || active_size > layout->maximum_capacity) {
            return std::unexpected(error::invalid_size);
        }

        return initialize(arena.first(layout->maximum_capacity), metadata,
                          *layout, active_size, minimum_block_size, false);
    }

    /**
     * Creates an allocator with metadata embedded at the end of arena.
     * The data capacity is reduced to leave room for the tree and reservation
     * bitmaps. initial_size defaults to the resulting data capacity.
     */
    [[nodiscard]] static std::expected<allocator, error>
    create_embedded(block_type arena,
                    size_type initial_size = npos,
                    size_type minimum_block_size = default_minimum_block_size) noexcept {
        if (arena.empty() || arena.data() == nullptr) {
            return std::unexpected(error::invalid_arena);
        }
        if (!valid_minimum_block_size(minimum_block_size)) {
            return std::unexpected(error::invalid_alignment);
        }
        if (reinterpret_cast<std::uintptr_t>(arena.data()) % minimum_block_size != 0) {
            return std::unexpected(error::invalid_alignment);
        }

        const auto embedded = find_embedded_layout(arena.size(), minimum_block_size);
        if (!embedded) {
            return std::unexpected(embedded.error());
        }

        const size_type active_size = initial_size == npos
            ? embedded->layout.maximum_capacity
            : align_down(initial_size, minimum_block_size);
        if (active_size == 0 || active_size > embedded->layout.maximum_capacity) {
            return std::unexpected(error::invalid_size);
        }

        auto metadata = arena.subspan(embedded->metadata_offset);
        return initialize(arena.first(embedded->layout.maximum_capacity), metadata,
                          embedded->layout, active_size, minimum_block_size, true);
    }

    /** Reconstructs a handle to an existing embedded allocator. */
    [[nodiscard]] static std::expected<allocator, error>
    attach_embedded(block_type arena,
                    size_type minimum_block_size = default_minimum_block_size) noexcept {
        if (arena.empty() || arena.data() == nullptr) {
            return std::unexpected(error::invalid_arena);
        }
        if (!valid_minimum_block_size(minimum_block_size)) {
            return std::unexpected(error::invalid_alignment);
        }
        if (reinterpret_cast<std::uintptr_t>(arena.data()) % minimum_block_size != 0) {
            return std::unexpected(error::invalid_alignment);
        }

        const auto embedded = find_embedded_layout(arena.size(), minimum_block_size);
        if (!embedded) {
            return std::unexpected(embedded.error());
        }
        auto metadata = arena.subspan(embedded->metadata_offset);
        metadata_header snapshot{};
        std::copy_n(metadata.data(), sizeof(snapshot),
                    reinterpret_cast<std::byte*>(&snapshot));
        if (!header_matches(snapshot, *embedded, minimum_block_size)) {
            return std::unexpected(error::corrupted_metadata);
        }
        // Copying an arena as bytes does not recreate C++ object lifetimes.
        // Re-establish the implicit-lifetime metadata objects before using them.
        auto* header = std::construct_at(
            reinterpret_cast<metadata_header*>(metadata.data()), snapshot);
        auto attached = from_existing(arena.first(header->maximum_capacity), metadata, *header);
        if (!attached || !attached->validate_existing_state()) {
            return std::unexpected(error::corrupted_metadata);
        }
        return attached;
    }

    /** Allocate at least requested_size bytes; zero requests allocate one minimum block. */
    [[nodiscard]] std::expected<block_type, error>
    allocate(size_type requested_size) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        const size_type size = requested_size == 0 ? 1 : requested_size;
        const auto target = request_layout(size);
        if (!target) {
            return std::unexpected(target.error());
        }
        const node_position position = find_free(target->depth);
        if (!valid(position)) {
            return std::unexpected(error::out_of_memory);
        }

        occupy_node(position);
        header_->free_size -= target->block_size;
        return block_at(position);
    }

    /** Allocate and zero-initialize count * element_size bytes, checking overflow. */
    [[nodiscard]] std::expected<block_type, error>
    allocate_zeroed(size_type count, size_type element_size) noexcept {
        size_type total = 1;
        if (count != 0 && element_size != 0) {
            if (count > std::numeric_limits<size_type>::max() / element_size) {
                return std::unexpected(error::invalid_size);
            }
            total = count * element_size;
        }
        auto block = allocate(total);
        if (!block) {
            return std::unexpected(block.error());
        }
        std::fill_n(block->begin(), total, std::byte{});
        return *block;
    }

    /**
     * Resize an allocation. A zero new size releases it. If current is empty,
     * this behaves like allocate(). On failure, current remains allocated.
     */
    [[nodiscard]] std::expected<block_type, error>
    reallocate(block_type current,
               size_type requested_size,
               reallocation_mode mode = reallocation_mode::preserve_contents) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        if (current.empty() && current.data() == nullptr) {
            // Match the original buddy_realloc(nullptr, size) contract:
            // it delegates to allocate(), including the zero-size minimum block.
            return allocate(requested_size);
        }

        const auto origin = locate(current);
        if (!origin) {
            return std::unexpected(origin.error());
        }
        if (range_has_reservations(origin->offset, origin->block_size)) {
            return std::unexpected(error::invalid_block);
        }

        if (requested_size == 0) {
            release_node(origin->position);
            header_->free_size += origin->block_size;
            return block_type{};
        }

        const auto target = request_layout(requested_size);
        if (!target) {
            return std::unexpected(target.error());
        }
        if (target->block_size > header_->maximum_capacity) {
            return std::unexpected(error::out_of_memory);
        }
        if (target->block_size == origin->block_size) {
            return block_at(origin->position);
        }

        if (target->block_size < origin->block_size) {
            shrink_in_place(origin->position, origin->block_size, target->block_size);
            header_->free_size += origin->block_size - target->block_size;
            return block_at_offset(origin->offset, target->block_size);
        }

        if (grow_in_place(origin->position, origin->block_size, target->block_size)) {
            header_->free_size -= target->block_size - origin->block_size;
            return block_at_offset(origin->offset, target->block_size);
        }

        // Release first so an adjacent free buddy can satisfy the larger request.
        release_node(origin->position);
        header_->free_size += origin->block_size;
        const node_position replacement = find_free(target->depth);
        if (!valid(replacement)) {
            occupy_node(origin->position);
            header_->free_size -= origin->block_size;
            return std::unexpected(error::out_of_memory);
        }

        occupy_node(replacement);
        header_->free_size -= target->block_size;

        const size_type new_offset = node_offset(replacement);
        if (mode == reallocation_mode::preserve_contents && new_offset != origin->offset) {
            std::memmove(
                backing_.data() + new_offset,
                backing_.data() + origin->offset,
                std::min(origin->block_size, target->block_size)
            );
        }
        return block_at(replacement);
    }

    /** Overflow-checked array reallocation. Zero dimensions follow realloc(ptr, 0). */
    [[nodiscard]] std::expected<block_type, error>
    reallocate_array(block_type current,
                     size_type count,
                     size_type element_size,
                     reallocation_mode mode = reallocation_mode::preserve_contents) noexcept {
        if (count == 0 || element_size == 0) {
            return reallocate(current, 0, mode);
        }
        if (count > std::numeric_limits<size_type>::max() / element_size) {
            return std::unexpected(error::invalid_size);
        }
        return reallocate(current, count * element_size, mode);
    }

    /** Release a complete block returned by allocate() or reallocate(). */
    [[nodiscard]] std::expected<void, error> deallocate(block_type block) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        const auto location = locate(block);
        if (!location || range_has_reservations(location->offset, location->block_size)) {
            return std::unexpected(error::invalid_block);
        }
        release_node(location->position);
        header_->free_size += location->block_size;
        return {};
    }

    /** Safer deallocation: requested_size must round to this exact buddy block. */
    [[nodiscard]] std::expected<void, error>
    deallocate(block_type block, size_type requested_size) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        const auto location = locate(block);
        if (!location || range_has_reservations(location->offset, location->block_size)) {
            return std::unexpected(error::invalid_block);
        }
        const auto request = request_layout(requested_size == 0 ? 1 : requested_size);
        if (!request || request->block_size != location->block_size) {
            return std::unexpected(error::size_mismatch);
        }
        release_node(location->position);
        header_->free_size += location->block_size;
        return {};
    }

    /**
     * Return the actual buddy block size for an allocation's exact starting
     * address. Interior pointers and reserved ranges are rejected.
     */
    [[nodiscard]] std::expected<size_type, error>
    allocation_size(const std::byte* address) const noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        const auto position = locate_address(address);
        if (!position) {
            return std::unexpected(position.error());
        }
        const size_type offset = node_offset(*position);
        const size_type length = node_size(*position);
        if (range_has_reservations(offset, length)) {
            return std::unexpected(error::invalid_block);
        }
        return length;
    }

    /** Reserve an aligned range, rounding its length up to whole minimum blocks. */
    [[nodiscard]] std::expected<block_type, error>
    reserve_range(block_type requested) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        const auto range = normalize_range(requested);
        if (!range) {
            return std::unexpected(range.error());
        }
        if (!range_is_free(range->first, range->second)) {
            return std::unexpected(error::range_conflict);
        }

        toggle_range(range->first, range->second, true);
        set_reservation_bits(range->first / header_->minimum_block_size,
                             range->second / header_->minimum_block_size, true);
        header_->reserved_size += range->second;
        header_->free_size -= range->second;
        return backing_.subspan(range->first, range->second);
    }

    /** Release only a range previously reserved with reserve_range(). */
    [[nodiscard]] std::expected<void, error>
    release_reserved_range(block_type requested) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        const auto range = normalize_range(requested);
        if (!range) {
            return std::unexpected(range.error());
        }
        const size_type first_block = range->first / header_->minimum_block_size;
        const size_type block_count = range->second / header_->minimum_block_size;
        if (!reservation_range_is_set(first_block, block_count)) {
            return std::unexpected(error::not_reserved);
        }

        toggle_range(range->first, range->second, false);
        set_reservation_bits(first_block, block_count, false);
        header_->reserved_size -= range->second;
        header_->free_size += range->second;
        return {};
    }

    /**
     * Explicitly unsafe counterpart of release_reserved_range(). The caller
     * must ensure that the entire range is currently reserved and contains no
     * ordinary allocations.
     */
    [[nodiscard]] std::expected<void, error>
    unsafe_release_range(block_type requested) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        const auto range = normalize_range(requested);
        if (!range) {
            return std::unexpected(range.error());
        }
        toggle_range(range->first, range->second, false);
        set_reservation_bits(range->first / header_->minimum_block_size,
                             range->second / header_->minimum_block_size, false);
        header_->reserved_size = header_->reserved_size >= range->second
            ? header_->reserved_size - range->second : 0;
        header_->free_size += range->second;
        return {};
    }

    /** True when the upper half of the active arena is entirely free. */
    [[nodiscard]] bool can_shrink() const noexcept {
        if (!is_initialized() || header_->memory_size < 2 * header_->minimum_block_size) {
            return false;
        }
        const size_type new_size = align_down(header_->memory_size / 2,
                                              header_->minimum_block_size);
        return new_size != 0 && range_is_free(new_size, header_->memory_size - new_size);
    }

    /**
     * Change the active arena size without moving its base address or metadata.
     * The new size is bounded by capacity(), which is fixed when the allocator
     * is created. Shrinking fails if an allocation or reservation would be
     * truncated; growing makes previously inactive bytes available again.
     *
     * For an embedded allocator, this is a logical resize inside the original
     * data capacity. It does not relocate the embedded metadata or enlarge the
     * original backing storage.
     */
    [[nodiscard]] std::expected<void, error> resize(size_type new_size) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        new_size = align_down(new_size, header_->minimum_block_size);
        if (new_size == 0 || new_size > header_->maximum_capacity) {
            return std::unexpected(error::resize_out_of_range);
        }
        if (new_size == header_->memory_size) {
            return {};
        }

        const size_type old_size = header_->memory_size;
        if (new_size < old_size) {
            const size_type removed = old_size - new_size;
            if (!range_is_free(new_size, removed)) {
                return std::unexpected(error::allocations_outside_new_size);
            }
            toggle_range(new_size, removed, true);
            header_->free_size -= removed;
        } else {
            const size_type added = new_size - old_size;
            toggle_range(old_size, added, false);
            header_->free_size += added;
        }
        header_->memory_size = new_size;
        return {};
    }

    [[nodiscard]] bool empty() const noexcept {
        return is_initialized() && header_->free_size == header_->memory_size;
    }

    [[nodiscard]] bool full() const noexcept {
        return is_initialized() && header_->free_size == 0;
    }

    [[nodiscard]] size_type arena_size() const noexcept {
        return is_initialized() ? header_->memory_size : 0;
    }

    /** Maximum data capacity established at creation; may exceed arena_size(). */
    [[nodiscard]] size_type capacity() const noexcept {
        return is_initialized() ? header_->maximum_capacity : 0;
    }

    /** Total free bytes; maintained incrementally on allocation and release. */
    [[nodiscard]] size_type free_size() const noexcept {
        return is_initialized() ? header_->free_size : 0;
    }

    [[nodiscard]] size_type minimum_block_size() const noexcept {
        return is_initialized() ? header_->minimum_block_size : 0;
    }

    [[nodiscard]] block_type arena() const noexcept {
        return is_initialized() ? backing_.first(header_->memory_size) : block_type{};
    }

    /** Fragmentation score calculated with the original C fixed-point algorithm. */
    [[nodiscard]] std::uint8_t fragmentation() const noexcept {
        if (!is_initialized() || header_->free_size == 0) {
            return 0;
        }

        size_type squared_sum = 0;
        collect_free_squared_units(root_position(), 0, header_->tree_capacity, squared_sum);
        // free_size is already maintained incrementally; avoid rebuilding the
        // total from every free interval during this diagnostic calculation.
        const size_type total_free_units = header_->free_size / header_->minimum_block_size;
        if (total_free_units == 0) {
            return 0;
        }

        constexpr size_type fractional_bits = 8;
        constexpr size_type fractional_mask = 255;
        size_type quality = (integer_square_root(squared_sum) << fractional_bits) /
                            total_free_units;
        quality *= quality;
        quality >>= fractional_bits;
        return static_cast<std::uint8_t>(fractional_mask - (quality & fractional_mask));
    }

    /**
     * Visit maximal free, allocated, and reserved blocks in address order.
     * The visitor receives block_info and returns true to continue or false to
     * stop. The result is true when the complete arena was visited.
     */
    template <class Visitor>
        requires std::predicate<Visitor&, block_info>
    [[nodiscard]] std::expected<bool, error> walk(Visitor&& visitor) const {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        bool completed = true;
        const auto wrapper = [&](block_info info) {
            if (!std::invoke(visitor, info)) {
                completed = false;
                return false;
            }
            return true;
        };
        (void)visit_node(root_position(), 0, header_->tree_capacity, wrapper);
        return completed;
    }

    /** Rebinds the data span after its contents have been copied to a new address. */
    [[nodiscard]] std::expected<void, error> rebind_arena(block_type new_arena) noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        if ((header_->flags & 1u) != 0) {
            // Embedded metadata moves with the arena. Reattach through the
            // metadata signature instead of retaining pointers into the old buffer.
            auto attached = attach_embedded(new_arena, header_->minimum_block_size);
            if (!attached) {
                return std::unexpected(attached.error());
            }
            move_from(*attached);
            return {};
        }
        if (new_arena.empty() || new_arena.data() == nullptr) {
            return std::unexpected(error::invalid_arena);
        }
        if (reinterpret_cast<std::uintptr_t>(new_arena.data()) % header_->minimum_block_size != 0) {
            return std::unexpected(error::invalid_alignment);
        }
        const size_type new_capacity = std::min(
            align_down(new_arena.size(), header_->minimum_block_size),
            header_->tree_capacity);
        if (new_capacity < header_->memory_size) {
            return std::unexpected(error::allocations_outside_new_size);
        }
        const auto new_backing = new_arena.first(new_capacity);
        if (ranges_overlap(new_backing, metadata_)) {
            return std::unexpected(error::metadata_overlap);
        }
        backing_ = new_backing;
        header_->maximum_capacity = new_capacity;
        return {};
    }

    /**
     * Rebuild an embedded allocator in a different, already-copied arena.
     * The returned allocator may have a different tree order and metadata
     * offset. Existing allocated and reserved blocks keep their byte offsets.
     *
     * The new span must not overlap the current embedded storage. Copy the
     * old arena bytes to the new storage before calling this function; user
     * payload bytes are not copied by the allocator. Any live or reserved
     * block that would fall outside new_active_size causes failure. This is an
     * rvalue-qualified operation: success consumes and invalidates the old
     * handle; failure leaves it usable.
     */
    [[nodiscard]] std::expected<allocator, error>
    resize_embedded(block_type new_arena, size_type new_active_size = npos) && noexcept {
        if (!is_initialized()) {
            return std::unexpected(error::allocator_moved_from);
        }
        if ((header_->flags & 1u) == 0) {
            return std::unexpected(error::invalid_metadata);
        }
        if (new_arena.empty() || new_arena.data() == nullptr) {
            return std::unexpected(error::invalid_arena);
        }
        if (reinterpret_cast<std::uintptr_t>(new_arena.data()) % header_->minimum_block_size != 0) {
            return std::unexpected(error::invalid_alignment);
        }

        // Embedded storage is the contiguous span from the data start through
        // the metadata tail (including any alignment padding between them).
        const auto storage_begin = reinterpret_cast<std::uintptr_t>(backing_.data());
        const auto metadata_begin = reinterpret_cast<std::uintptr_t>(metadata_.data());
        if (metadata_.size() > std::numeric_limits<std::uintptr_t>::max() - metadata_begin) {
            return std::unexpected(error::corrupted_metadata);
        }
        const auto metadata_end = metadata_begin + metadata_.size();
        if (metadata_end < storage_begin) {
            return std::unexpected(error::corrupted_metadata);
        }
        const block_type old_storage{
            backing_.data(), static_cast<size_type>(metadata_end - storage_begin)};
        if (ranges_overlap(old_storage, new_arena)) {
            return std::unexpected(error::metadata_overlap);
        }

        const auto embedded = find_embedded_layout(new_arena.size(), header_->minimum_block_size);
        if (!embedded) {
            return std::unexpected(embedded.error());
        }
        const size_type active_size = new_active_size == npos
            ? embedded->layout.maximum_capacity
            : align_down(new_active_size, header_->minimum_block_size);
        if (active_size == 0 || active_size > embedded->layout.maximum_capacity) {
            return std::unexpected(error::resize_out_of_range);
        }

        // Preflight before writing the new metadata tail. In particular, a
        // failed shrink must not overwrite payload bytes in the destination.
        error preflight_error = error::allocations_outside_new_size;
        const auto preflight = walk([&](block_info info) noexcept {
            if (info.kind == block_kind::free) {
                return true;
            }
            const size_type offset = static_cast<size_type>(info.memory.data() - backing_.data());
            if (offset > active_size || info.memory.size() > active_size - offset) {
                return false;
            }
            return true;
        });
        if (!preflight) {
            return std::unexpected(preflight.error());
        }
        if (!*preflight) {
            return std::unexpected(preflight_error);
        }

        auto replacement_result = create_embedded(
            new_arena, active_size, header_->minimum_block_size);
        if (!replacement_result) {
            return std::unexpected(replacement_result.error());
        }
        allocator replacement = std::move(*replacement_result);
        error transfer_error = error::corrupted_metadata;
        bool transfer_failed = false;

        const auto visited = walk([&](block_info info) noexcept {
            if (info.kind == block_kind::free) {
                return true;
            }
            const size_type offset = static_cast<size_type>(info.memory.data() - backing_.data());
            if (offset > active_size || info.memory.size() > active_size - offset) {
                transfer_error = error::allocations_outside_new_size;
                transfer_failed = true;
                return false;
            }

            std::expected<void, error> transferred;
            if (info.kind == block_kind::reserved) {
                auto reserved = replacement.reserve_range(
                    {new_arena.data() + offset, info.memory.size()});
                if (!reserved) {
                    transferred = std::unexpected(reserved.error());
                }
            } else {
                transferred = replacement.mark_existing_allocation(offset, info.memory.size());
            }
            if (!transferred) {
                transfer_error = transferred.error();
                transfer_failed = true;
                return false;
            }
            return true;
        });
        if (!visited) {
            return std::unexpected(visited.error());
        }
        if (transfer_failed || !*visited) {
            return std::unexpected(transfer_error);
        }
        allocator result = std::move(replacement);
        reset_handle();
        return result;
    }

private:
    struct metadata_header {
        std::uint64_t magic{};
        std::uint32_t flags{};
        size_type minimum_block_size{};
        size_type maximum_capacity{};
        size_type memory_size{};
        size_type tree_capacity{};
        size_type order{};
        size_type tree_bit_count{};
        size_type tree_byte_count{};
        size_type reservation_word_count{};
        size_type tree_offset{};
        size_type reservation_offset{};
        size_type size_table_offset{};
        size_type size_table_count{};
        size_type free_size{};
        size_type reserved_size{};
    };

    struct layout_info {
        size_type maximum_capacity{};
        size_type tree_capacity{};
        size_type leaves{};
        size_type order{};
        size_type tree_bit_count{};
        size_type tree_byte_count{};
        size_type reservation_word_count{};
        size_type tree_offset{};
        size_type reservation_offset{};
        size_type size_table_offset{};
        size_type size_table_count{};
        size_type metadata_size{};
    };

    struct embedded_layout_info {
        layout_info layout{};
        size_type metadata_offset{};
    };

    struct node_position {
        size_type index{};
        size_type depth{};
    };

    struct internal_position {
        size_type bitset_location{};
        size_type local_offset{};
    };

    struct request_info {
        size_type block_size{};
        size_type depth{};
    };

    struct block_location {
        node_position position{};
        size_type offset{};
        size_type block_size{};
    };

    static constexpr std::uint64_t metadata_magic = 0x4255444459433233ull; // BUDDYC23
    static constexpr size_type root_index = 1;
    static constexpr size_type word_bits = std::numeric_limits<std::uint64_t>::digits;

    allocator(block_type backing,
              std::span<std::byte> metadata,
              metadata_header* header,
              std::span<std::byte> tree_bits,
              std::span<std::uint64_t> reservations,
              std::span<const size_type> size_table) noexcept
        : backing_(backing), metadata_(metadata), header_(header),
          tree_bits_(tree_bits), reservations_(reservations), size_table_(size_table),
          minimum_shift_(static_cast<size_type>(std::countr_zero(header->minimum_block_size))) {}

    [[nodiscard]] static constexpr bool valid_minimum_block_size(size_type value) noexcept {
        return value >= default_minimum_block_size && std::has_single_bit(value);
    }

    [[nodiscard]] static constexpr size_type align_down(size_type value, size_type alignment) noexcept {
        return value & ~(alignment - 1);
    }

    [[nodiscard]] static constexpr bool add_overflow(size_type a, size_type b) noexcept {
        return a > std::numeric_limits<size_type>::max() - b;
    }

    [[nodiscard]] static constexpr bool multiply_overflow(size_type a, size_type b) noexcept {
        return b != 0 && a > std::numeric_limits<size_type>::max() / b;
    }

    [[nodiscard]] static constexpr bool align_up_checked(
        size_type value, size_type alignment, size_type& result) noexcept {
        if (alignment == 0 || !std::has_single_bit(alignment)) {
            return false;
        }
        const size_type remainder = value & (alignment - 1);
        if (remainder == 0) {
            result = value;
            return true;
        }
        const size_type increment = alignment - remainder;
        if (add_overflow(value, increment)) {
            return false;
        }
        result = value + increment;
        return true;
    }

    [[nodiscard]] static constexpr size_type tree_order_for_blocks(size_type blocks) noexcept {
        if (blocks == 0) {
            return 0;
        }
        const size_type leaves = std::bit_ceil(blocks);
        return static_cast<size_type>(std::bit_width(leaves));
    }

    [[nodiscard]] static constexpr size_type tree_size_for_order(size_type order,
                                                                  size_type target_order) noexcept {
        size_type total = 0;
        size_type nodes = 1;
        while (order > target_order) {
            if (multiply_overflow(order, nodes) || add_overflow(total, order * nodes)) {
                return 0;
            }
            total += order * nodes;
            --order;
            if (order > target_order) {
                if (nodes > std::numeric_limits<size_type>::max() / 2) {
                    return 0;
                }
                nodes *= 2;
            }
        }
        return total;
    }

    [[nodiscard]] static std::expected<layout_info, error>
    layout_for_order(size_type maximum_capacity, size_type minimum_block_size,
                     size_type order) noexcept {
        if (order == 0 || order > std::numeric_limits<size_type>::digits) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type leaves = size_type{1} << (order - 1);
        if (multiply_overflow(leaves, minimum_block_size)) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type tree_capacity = leaves * minimum_block_size;
        const size_type bit_count = tree_size_for_order(order, 0);
        if (bit_count == 0 || add_overflow(bit_count, 7)) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type tree_bytes = (bit_count + 7) / 8;
        const size_type reservation_words = leaves / word_bits +
            static_cast<size_type>((leaves % word_bits) != 0);
        if (multiply_overflow(reservation_words, sizeof(std::uint64_t))) {
            return std::unexpected(error::invalid_arena);
        }
        constexpr size_type alignment =
            alignof(std::uint64_t) > alignof(size_type)
                ? alignof(std::uint64_t) : alignof(size_type);
        size_type tree_offset{};
        if (!align_up_checked(sizeof(metadata_header), alignment, tree_offset) ||
            add_overflow(tree_offset, tree_bytes)) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type tree_end = tree_offset + tree_bytes;
        size_type reservation_offset{};
        if (!align_up_checked(tree_end, alignment, reservation_offset)) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type reservation_bytes = reservation_words * sizeof(std::uint64_t);
        if (add_overflow(reservation_offset, reservation_bytes)) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type reservation_end = reservation_offset + reservation_bytes;
        size_type size_table_offset{};
        if (!align_up_checked(reservation_end, alignof(size_type), size_table_offset)) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type size_table_count = order + 1;
        if (multiply_overflow(size_table_count, sizeof(size_type))) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type size_table_bytes = size_table_count * sizeof(size_type);
        if (add_overflow(size_table_offset, size_table_bytes)) {
            return std::unexpected(error::invalid_arena);
        }
        return layout_info{
            maximum_capacity,
            tree_capacity,
            leaves,
            order,
            bit_count,
            tree_bytes,
            reservation_words,
            tree_offset,
            reservation_offset,
            size_table_offset,
            size_table_count,
            size_table_offset + size_table_bytes,
        };
    }

    [[nodiscard]] static std::expected<layout_info, error>
    make_layout(size_type maximum_arena_size, size_type minimum_block_size) noexcept {
        if (!valid_minimum_block_size(minimum_block_size)) {
            return std::unexpected(error::invalid_alignment);
        }
        const size_type capacity = align_down(maximum_arena_size, minimum_block_size);
        if (capacity == 0) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type blocks = capacity / minimum_block_size;
        const size_type order = tree_order_for_blocks(blocks);
        const size_type leaves = size_type{1} << (order - 1);
        if (multiply_overflow(leaves, minimum_block_size)) {
            return std::unexpected(error::invalid_arena);
        }
        return layout_for_order(capacity, minimum_block_size, order);
    }

    [[nodiscard]] static std::expected<embedded_layout_info, error>
    find_embedded_layout(size_type arena_size, size_type minimum_block_size) noexcept {
        if (!valid_minimum_block_size(minimum_block_size)) {
            return std::unexpected(error::invalid_alignment);
        }
        const size_type possible_blocks = arena_size / minimum_block_size;
        if (possible_blocks == 0) {
            return std::unexpected(error::invalid_arena);
        }
        const size_type largest_order = tree_order_for_blocks(possible_blocks);
        constexpr size_type metadata_alignment = alignof(metadata_header);

        for (size_type order = largest_order; order != 0; --order) {
            const auto candidate = layout_for_order(0, minimum_block_size, order);
            if (!candidate || arena_size < candidate->metadata_size) {
                continue;
            }
            const size_type metadata_offset =
                align_down(arena_size - candidate->metadata_size, metadata_alignment);
            const size_type data_capacity = align_down(metadata_offset, minimum_block_size);
            const size_type blocks = data_capacity / minimum_block_size;
            if (blocks == 0 || tree_order_for_blocks(blocks) != order) {
                continue;
            }
            auto layout = *candidate;
            layout.maximum_capacity = data_capacity;
            return embedded_layout_info{layout, metadata_offset};
        }
        return std::unexpected(error::invalid_arena);
    }

    [[nodiscard]] static bool ranges_overlap(block_type a, std::span<std::byte> b) noexcept {
        const auto a_begin = reinterpret_cast<std::uintptr_t>(a.data());
        const auto b_begin = reinterpret_cast<std::uintptr_t>(b.data());
        if (a.size() > std::numeric_limits<std::uintptr_t>::max() - a_begin ||
            b.size() > std::numeric_limits<std::uintptr_t>::max() - b_begin) {
            return true;
        }
        const auto a_end = a_begin + a.size();
        const auto b_end = b_begin + b.size();
        return a_begin < b_end && b_begin < a_end;
    }

    [[nodiscard]] static std::expected<allocator, error>
    initialize(block_type backing,
               std::span<std::byte> metadata,
               const layout_info& layout,
               size_type active_size,
               size_type minimum_block_size,
               bool embedded) noexcept {
        if (metadata.size() < layout.metadata_size ||
            reinterpret_cast<std::uintptr_t>(metadata.data()) % alignof(metadata_header) != 0) {
            return std::unexpected(error::invalid_metadata);
        }
        auto* header = std::construct_at(reinterpret_cast<metadata_header*>(metadata.data()));
        *header = metadata_header{
            metadata_magic,
            static_cast<std::uint32_t>(embedded ? 1u : 0u),
            minimum_block_size,
            layout.maximum_capacity,
            active_size,
            layout.tree_capacity,
            layout.order,
            layout.tree_bit_count,
            layout.tree_byte_count,
            layout.reservation_word_count,
            layout.tree_offset,
            layout.reservation_offset,
            layout.size_table_offset,
            layout.size_table_count,
            active_size,
            0,
        };

        auto tree_bits = metadata.subspan(layout.tree_offset, layout.tree_byte_count);
        std::fill(tree_bits.begin(), tree_bits.end(), std::byte{});

        auto* reservation_data = reinterpret_cast<std::uint64_t*>(metadata.data() + layout.reservation_offset);
        for (size_type i = 0; i < layout.reservation_word_count; ++i) {
            std::construct_at(reservation_data + i, std::uint64_t{0});
        }
        std::span<std::uint64_t> reservations{reservation_data, layout.reservation_word_count};

        auto* size_table_data = reinterpret_cast<size_type*>(metadata.data() + layout.size_table_offset);
        for (size_type i = 0; i < layout.size_table_count; ++i) {
            std::construct_at(size_table_data + i, tree_size_for_order(layout.order, i));
        }
        std::span<const size_type> size_table{size_table_data, layout.size_table_count};

        allocator result{backing, metadata, header, tree_bits, reservations, size_table};
        if (active_size < layout.tree_capacity) {
            result.toggle_range(active_size, layout.tree_capacity - active_size, true);
        }
        return result;
    }

    [[nodiscard]] static bool header_matches(const metadata_header& header,
                                             const embedded_layout_info& embedded,
                                             size_type minimum_block_size) noexcept {
        return header.magic == metadata_magic &&
               (header.flags & 1u) != 0 &&
               header.minimum_block_size == minimum_block_size &&
               header.maximum_capacity == embedded.layout.maximum_capacity &&
               header.order == embedded.layout.order &&
               header.tree_capacity == embedded.layout.tree_capacity &&
               header.tree_bit_count == embedded.layout.tree_bit_count &&
               header.tree_byte_count == embedded.layout.tree_byte_count &&
               header.reservation_word_count == embedded.layout.reservation_word_count &&
               header.tree_offset == embedded.layout.tree_offset &&
               header.reservation_offset == embedded.layout.reservation_offset &&
               header.size_table_offset == embedded.layout.size_table_offset &&
               header.size_table_count == embedded.layout.size_table_count &&
               header.memory_size <= header.maximum_capacity &&
               header.memory_size != 0 &&
               header.memory_size % minimum_block_size == 0 &&
               header.free_size <= header.memory_size &&
               header.free_size % minimum_block_size == 0 &&
               header.reserved_size <= header.memory_size - header.free_size;
    }

    [[nodiscard]] static std::expected<allocator, error>
    from_existing(block_type backing, std::span<std::byte> metadata,
                  metadata_header& header) noexcept {
        if (header.tree_offset > metadata.size() ||
            header.tree_byte_count > metadata.size() - header.tree_offset ||
            header.reservation_offset > metadata.size() ||
            header.reservation_word_count >
                (metadata.size() - header.reservation_offset) / sizeof(std::uint64_t) ||
            header.size_table_offset > metadata.size() ||
            header.size_table_count >
                (metadata.size() - header.size_table_offset) / sizeof(size_type) ||
            header.size_table_count != header.order + 1) {
            return std::unexpected(error::corrupted_metadata);
        }
        auto tree_bits = metadata.subspan(header.tree_offset, header.tree_byte_count);
        auto* reservation_data = reinterpret_cast<std::uint64_t*>(metadata.data() + header.reservation_offset);
        for (size_type i = 0; i < header.reservation_word_count; ++i) {
            std::uint64_t value{};
            std::copy_n(metadata.data() + header.reservation_offset + i * sizeof(value),
                        sizeof(value), reinterpret_cast<std::byte*>(&value));
            std::construct_at(reservation_data + i, value);
        }
        std::span<std::uint64_t> reservations{reservation_data, header.reservation_word_count};
        auto* size_table_data = reinterpret_cast<size_type*>(metadata.data() + header.size_table_offset);
        for (size_type i = 0; i < header.size_table_count; ++i) {
            size_type value{};
            std::copy_n(metadata.data() + header.size_table_offset + i * sizeof(value),
                        sizeof(value), reinterpret_cast<std::byte*>(&value));
            std::construct_at(size_table_data + i, value);
        }
        std::span<const size_type> size_table{size_table_data, header.size_table_count};
        for (size_type i = 0; i < size_table.size(); ++i) {
            if (size_table[i] != tree_size_for_order(header.order, i)) {
                return std::unexpected(error::corrupted_metadata);
            }
        }
        return allocator{backing, metadata, &header, tree_bits, reservations, size_table};
    }

    [[nodiscard]] bool validate_existing_state() const noexcept {
        if (!is_initialized() ||
            header_->minimum_block_size < default_minimum_block_size ||
            !std::has_single_bit(header_->minimum_block_size) ||
            header_->memory_size == 0 ||
            header_->memory_size > header_->maximum_capacity ||
            header_->maximum_capacity > header_->tree_capacity ||
            header_->free_size > header_->memory_size ||
            header_->free_size % header_->minimum_block_size != 0 ||
            header_->reserved_size > header_->memory_size - header_->free_size ||
            header_->reserved_size % header_->minimum_block_size != 0) {
            return false;
        }

        if (header_->tree_bit_count % 8u != 0u) {
            const auto used_bits = static_cast<unsigned int>(header_->tree_bit_count % 8u);
            const auto valid_mask = static_cast<std::uint8_t>((1u << used_bits) - 1u);
            const auto final_byte = std::to_integer<std::uint8_t>(tree_bits_.back());
            if ((final_byte & static_cast<std::uint8_t>(~valid_mask)) != 0) {
                return false;
            }
        }

        // Validate every stored per-level unary prefix. Each node summary
        // must retain the canonical 1...10...0 representation.
        for (size_type depth = 1; depth <= header_->order; ++depth) {
            const size_type width = header_->order - depth + 1;
            const size_type first_node = size_type{1} << (depth - 1u);
            const size_type node_count = first_node;
            const size_type row_offset = size_table_[width];
            for (size_type node = 0; node < node_count; ++node) {
                const size_type first_bit = row_offset + width * node;
                const size_type status = count_tree_bits(first_bit, width);
                for (size_type bit = 0; bit < width; ++bit) {
                    if (test_tree_bit(first_bit + bit) != (bit < status)) {
                        return false;
                    }
                }
            }
        }

        const size_type leaf_count = header_->tree_capacity / header_->minimum_block_size;
        const size_type active_leaf_count = header_->memory_size / header_->minimum_block_size;
        size_type reserved_leaf_count = 0;
        for (size_type word_index = 0; word_index < reservations_.size(); ++word_index) {
            const std::uint64_t word = reservations_[word_index];
            const size_type first_leaf = word_index * word_bits;
            const size_type valid_count = std::min(word_bits, leaf_count - first_leaf);
            const std::uint64_t valid_mask = low_bits_mask(valid_count);
            if ((word & ~valid_mask) != 0) {
                return false;
            }
            reserved_leaf_count += static_cast<size_type>(std::popcount(word));
            if (first_leaf >= active_leaf_count && word != 0) {
                return false;
            }
            if (first_leaf < active_leaf_count) {
                const size_type active_in_word = std::min(valid_count, active_leaf_count - first_leaf);
                if (active_in_word < valid_count &&
                    (word & (valid_mask & ~low_bits_mask(active_in_word))) != 0) {
                    return false;
                }
            }
        }
        if (reserved_leaf_count > std::numeric_limits<size_type>::max() /
                                      header_->minimum_block_size ||
            reserved_leaf_count * header_->minimum_block_size != header_->reserved_size) {
            return false;
        }

        size_type walked_free = 0;
        size_type walked_allocated = 0;
        size_type walked_reserved = 0;
        const auto result = visit_node(root_position(), 0, header_->tree_capacity,
            [&](block_info info) noexcept {
                auto* target = info.kind == block_kind::free ? &walked_free
                    : info.kind == block_kind::allocated ? &walked_allocated
                    : &walked_reserved;
                if (add_overflow(*target, info.memory.size())) {
                    return false;
                }
                *target += info.memory.size();
                return true;
            });
        if (!result || walked_free != header_->free_size ||
            walked_reserved != header_->reserved_size ||
            walked_allocated > header_->memory_size ||
            walked_free > header_->memory_size - walked_allocated ||
            walked_reserved != header_->memory_size - walked_free - walked_allocated) {
            return false;
        }
        return true;
    }

    void reset_handle() noexcept {
        backing_ = {};
        metadata_ = {};
        header_ = nullptr;
        tree_bits_ = {};
        reservations_ = {};
        size_table_ = {};
        minimum_shift_ = 0;
    }

    void move_from(allocator& other) noexcept {
        backing_ = std::exchange(other.backing_, {});
        metadata_ = std::exchange(other.metadata_, {});
        header_ = std::exchange(other.header_, nullptr);
        tree_bits_ = std::exchange(other.tree_bits_, {});
        reservations_ = std::exchange(other.reservations_, {});
        size_table_ = std::exchange(other.size_table_, {});
        minimum_shift_ = std::exchange(other.minimum_shift_, 0);
    }

    [[nodiscard]] bool is_initialized() const noexcept {
        return header_ != nullptr;
    }

    [[nodiscard]] static constexpr node_position root_position() noexcept {
        return {root_index, 1};
    }

    [[nodiscard]] bool valid(node_position position) const noexcept {
        return position.index >= 1 && position.depth >= 1 &&
               position.depth <= header_->order &&
               position.index < (size_type{1} << header_->order);
    }

    [[nodiscard]] size_type local_width(node_position position) const noexcept {
        return header_->order - position.depth + 1;
    }

    [[nodiscard]] size_type row_start(node_position position) const noexcept {
        return size_type{1} << (position.depth - 1);
    }

    [[nodiscard]] size_type node_offset(node_position position) const noexcept {
        const size_type leaf_index = position.index - row_start(position);
        return leaf_index * (header_->tree_capacity >> (position.depth - 1));
    }

    [[nodiscard]] size_type node_size(node_position position) const noexcept {
        return header_->tree_capacity >> (position.depth - 1);
    }

    [[nodiscard]] node_position left_child(node_position position) const noexcept {
        return {position.index * 2, position.depth + 1};
    }

    [[nodiscard]] node_position right_child(node_position position) const noexcept {
        return {position.index * 2 + 1, position.depth + 1};
    }

    [[nodiscard]] node_position parent(node_position position) const noexcept {
        return {position.index / 2, position.depth - 1};
    }

    [[nodiscard]] node_position sibling(node_position position) const noexcept {
        position.index ^= 1u;
        return position;
    }

    [[nodiscard]] internal_position internal(node_position position) const noexcept {
        const size_type width = local_width(position);
        const size_type row_offset = size_table_[width];
        const size_type local_index = position.index - row_start(position);
        return {row_offset + width * local_index, width};
    }

    [[nodiscard]] bool test_tree_bit(size_type position) const noexcept {
        const size_type byte_index = position / 8;
        const auto mask = static_cast<std::uint8_t>(1u << (position % 8));
        return (std::to_integer<std::uint8_t>(tree_bits_[byte_index]) & mask) != 0;
    }

    void set_tree_bit(size_type position) noexcept {
        const size_type byte_index = position / 8;
        const auto mask = static_cast<std::uint8_t>(1u << (position % 8));
        const auto value = static_cast<std::uint8_t>(std::to_integer<std::uint8_t>(tree_bits_[byte_index]) | mask);
        tree_bits_[byte_index] = static_cast<std::byte>(value);
    }

    void clear_tree_bit(size_type position) noexcept {
        const size_type byte_index = position / 8;
        const auto mask = static_cast<std::uint8_t>(~(1u << (position % 8)));
        const auto value = static_cast<std::uint8_t>(std::to_integer<std::uint8_t>(tree_bits_[byte_index]) & mask);
        tree_bits_[byte_index] = static_cast<std::byte>(value);
    }

    void set_tree_bits(size_type first, size_type count) noexcept {
        if (count == 0) {
            return;
        }
        const size_type last = first + count;
        const size_type first_byte = first / 8;
        const size_type last_byte = (last - 1) / 8;
        const size_type first_bit = first % 8;
        const size_type last_bit = (last - 1) % 8;
        if (first_byte == last_byte) {
            const auto low = static_cast<unsigned int>(0xFFu << first_bit);
            const auto high = static_cast<unsigned int>(0xFFu >> (7u - static_cast<unsigned int>(last_bit)));
            const auto mask = static_cast<std::uint8_t>(low & high);
            tree_bits_[first_byte] |= static_cast<std::byte>(mask);
            return;
        }
        tree_bits_[first_byte] |= static_cast<std::byte>(static_cast<std::uint8_t>(0xFFu << first_bit));
        if (last_byte > first_byte + 1) {
            std::fill(tree_bits_.begin() + static_cast<std::ptrdiff_t>(first_byte + 1),
                      tree_bits_.begin() + static_cast<std::ptrdiff_t>(last_byte),
                      std::byte{0xFF});
        }
        const auto last_mask = static_cast<std::uint8_t>(0xFFu >> (7u - static_cast<unsigned int>(last_bit)));
        tree_bits_[last_byte] |= static_cast<std::byte>(last_mask);
    }

    void clear_tree_bits(size_type first, size_type count) noexcept {
        if (count == 0) {
            return;
        }
        const size_type last = first + count;
        const size_type first_byte = first / 8;
        const size_type last_byte = (last - 1) / 8;
        const size_type first_bit = first % 8;
        const size_type last_bit = (last - 1) % 8;
        if (first_byte == last_byte) {
            const auto low = static_cast<unsigned int>(0xFFu << first_bit);
            const auto high = static_cast<unsigned int>(0xFFu >> (7u - static_cast<unsigned int>(last_bit)));
            const auto mask = static_cast<std::uint8_t>(~(low & high));
            tree_bits_[first_byte] &= static_cast<std::byte>(mask);
            return;
        }
        tree_bits_[first_byte] &= static_cast<std::byte>(static_cast<std::uint8_t>(~(0xFFu << first_bit)));
        if (last_byte > first_byte + 1) {
            std::fill(tree_bits_.begin() + static_cast<std::ptrdiff_t>(first_byte + 1),
                      tree_bits_.begin() + static_cast<std::ptrdiff_t>(last_byte),
                      std::byte{});
        }
        const auto last_mask = static_cast<std::uint8_t>(~(0xFFu >> (7u - static_cast<unsigned int>(last_bit))));
        tree_bits_[last_byte] &= static_cast<std::byte>(last_mask);
    }

    [[nodiscard]] size_type count_tree_bits_nonzero(size_type first, size_type count) const noexcept {
        // Every node summary is a unary prefix (111...1100...00). Count only
        // the leading one-run and stop at the first zero instead of popcounting
        // every byte in the summary, which is usually more work than needed.
        size_type result = 0;
        while (count != 0) {
            const size_type byte_index = first >> 3;
            const unsigned bit_offset = static_cast<unsigned>(first & 7u);
            const size_type available = 8u - bit_offset;
            const size_type take = std::min(count, available);
            const auto byte = std::to_integer<std::uint8_t>(tree_bits_[byte_index]);
            const auto shifted = static_cast<std::uint8_t>(byte >> bit_offset);
            const size_type run = static_cast<size_type>(std::countr_one(shifted));
            const size_type consumed = std::min(run, take);
            result += consumed;
            if (consumed != take) {
                break;
            }
            first += take;
            count -= take;
        }
        return result;
    }

    [[nodiscard]] size_type count_tree_bits(size_type first, size_type count) const noexcept {
        if (count == 0 || !test_tree_bit(first)) {
            return 0;
        }
        return count_tree_bits_nonzero(first, count);
    }

    [[nodiscard]] size_type read_status(internal_position location) const noexcept {
        return count_tree_bits(location.bitset_location, location.local_offset);
    }

    [[nodiscard]] size_type read_status(node_position position) const noexcept {
        return read_status(internal(position));
    }

    void write_status(internal_position location, size_type value) noexcept {
        clear_tree_bits(location.bitset_location, location.local_offset);
        set_tree_bits(location.bitset_location, value);
    }

    // Unary summaries are prefixes of set bits. The two boundary bits tell
    // whether the current prefix is equal to, shorter than, or longer than the
    // desired status, so ancestor updates avoid a popcount of the old parent.
    [[nodiscard]] bool update_status_to(internal_position location, size_type next) noexcept {
        const size_type first = location.bitset_location;
        const size_type width = location.local_offset;
        if (next == 0) {
            if (!test_tree_bit(first)) {
                return false;
            }
            clear_tree_bits(first, width);
            return true;
        }
        if (next > width) {
            return false;
        }
        if (!test_tree_bit(first + next - 1)) {
            // Existing prefix is shorter; setting the desired prefix is enough.
            set_tree_bits(first, next);
            return true;
        }
        if (next < width && test_tree_bit(first + next)) {
            // Existing prefix is longer; trim everything after the new end.
            clear_tree_bits(first + next, width - next);
            return true;
        }
        return false;
    }

    void write_status(node_position position, size_type value) noexcept {
        write_status(internal(position), value);
    }

    [[nodiscard]] bool compare_status(internal_position location, size_type value) const noexcept {
        return test_tree_bit(location.bitset_location + value - 1);
    }


    // The original C implementation uses an integer square root as part of
    // its 8-bit fixed-point fragmentation calculation. Keep this identical so
    // the public score remains compatible across the C and C++ implementations.
    [[nodiscard]] static size_type integer_square_root(size_type value) noexcept {
        size_type result = 0;
        size_type cursor = (std::numeric_limits<size_type>::max() -
                            (std::numeric_limits<size_type>::max() >> 1)) >> 1;
        while (cursor > value) {
            cursor >>= 2;
        }
        while (cursor != 0) {
            if (value >= result + cursor) {
                value -= result + cursor;
                result += 2 * cursor;
            }
            result >>= 1;
            cursor >>= 2;
        }
        return result;
    }

    // Clear all descendants of a node a row at a time. Descendant bit ranges
    // are contiguous within each tree row, so this avoids a recursive walk of
    // every node when a whole subtree is known to be uniformly free/occupied.
    void clear_descendant_bits(node_position position) noexcept {
        const size_type first_in_row = position.index - row_start(position);
        for (size_type depth = position.depth + 1; depth <= header_->order; ++depth) {
            const size_type relative_depth = depth - position.depth;
            const size_type descendant_count = size_type{1} << relative_depth;
            const size_type first_descendant = first_in_row << relative_depth;
            const size_type width = header_->order - depth + 1;
            const size_type first_bit = size_table_[width] + width * first_descendant;
            clear_tree_bits(first_bit, width * descendant_count);
        }
    }

    void update_ancestors(node_position position, size_type current_status) noexcept {
        internal_position current_location = internal(position);
        while (position.index != root_index) {
            const size_type sibling_location = current_location.bitset_location +
                ((position.index & 1u) == 0
                    ? current_location.local_offset
                    : size_type{0} - current_location.local_offset);
            const size_type sibling_status = test_tree_bit(sibling_location)
                ? count_tree_bits_nonzero(sibling_location, current_location.local_offset)
                : 0;
            position = parent(position);
            current_location = internal(position);
            const size_type next_status = (current_status != 0 || sibling_status != 0)
                ? std::min(current_status, sibling_status) + 1
                : 0;
            if (!update_status_to(current_location, next_status)) {
                return;
            }
            current_status = next_status;
        }
    }

    [[nodiscard]] internal_position child_internal(node_position parent_position,
                                                   bool right) const noexcept {
        const size_type child_width = local_width(parent_position) - 1;
        const size_type parent_local_index =
            parent_position.index - row_start(parent_position);
        const size_type child_index = parent_local_index * 2 +
            static_cast<size_type>(right);
        return {size_table_[child_width] + child_width * child_index, child_width};
    }

    void mark_node(node_position position) noexcept {
        const internal_position location = internal(position);
        set_tree_bits(location.bitset_location, location.local_offset);
        update_ancestors(position, location.local_offset);
    }

    // Node summaries are kept canonical by clearing descendants when a whole
    // subtree becomes free or is merged into one allocation.
    void occupy_node(node_position position) noexcept {
        mark_node(position);
    }

    // Growing into a buddy merges multiple prior states into one allocation.
    // Its descendants must be discarded before marking the parent occupied.
    void occupy_node_clearing_descendants(node_position position) noexcept {
        clear_descendant_bits(position);
        mark_node(position);
    }

    void release_node(node_position position) noexcept {
        const internal_position location = internal(position);
        clear_tree_bits(location.bitset_location, location.local_offset);
        update_ancestors(position, 0);
    }

    // Search the canonical unary summaries directly. Range changes clear
    // descendants locally, so no stale-summary fallback is needed.
    [[nodiscard]] node_position find_free(size_type target_depth) noexcept {
        node_position current = root_position();
        size_type target_status = target_depth - 1;
        size_type current_depth = 1;
        if (compare_status(internal(current), target_status + 1)) {
            return {};
        }

        while (current_depth != target_depth) {
            --target_status;
            ++current_depth;
            const node_position left = left_child(current);
            const node_position right = right_child(current);
            const internal_position left_location = child_internal(current, false);
            const internal_position right_location{
                left_location.bitset_location + left_location.local_offset,
                left_location.local_offset};

            if (test_tree_bit(left_location.bitset_location + target_status)) {
                current = right;
            } else if (test_tree_bit(right_location.bitset_location + target_status)) {
                current = left;
            } else {
                const size_type right_status = test_tree_bit(right_location.bitset_location)
                    ? count_tree_bits_nonzero(right_location.bitset_location,
                                              right_location.local_offset)
                    : 0;
                if (right_status != 0 &&
                    test_tree_bit(left_location.bitset_location + right_status - 1)) {
                    current = left;
                } else {
                    current = right_status == 0 ? left : right;
                }
            }
        }
        return current;
    }

    [[nodiscard]] std::expected<request_info, error>
    request_layout(size_type requested_size) const noexcept {
        if (requested_size == 0) {
            requested_size = 1;
        }
        if (requested_size > header_->memory_size) {
            return std::unexpected(error::out_of_memory);
        }

        // Requests are rounded to a power-of-two byte size, clamped to the
        // allocator's minimum block. This avoids variable division/modulo.
        const size_type requested_shift = static_cast<size_type>(std::bit_width(requested_size - 1));
        const size_type block_shift = std::max(minimum_shift_, requested_shift);
        const size_type target_order = block_shift - minimum_shift_;
        if (target_order >= header_->order) {
            return std::unexpected(error::out_of_memory);
        }

        const size_type target_depth = header_->order - target_order;
        const size_type block_size = header_->tree_capacity >> (target_depth - 1);
        if (block_size > header_->memory_size) {
            return std::unexpected(error::out_of_memory);
        }
        return request_info{block_size, target_depth};
    }

    [[nodiscard]] block_type block_at(node_position position) const noexcept {
        const size_type offset = node_offset(position);
        const size_type size = node_size(position);
        return backing_.subspan(offset, size);
    }

    [[nodiscard]] block_type block_at_offset(size_type offset, size_type size) const noexcept {
        return backing_.subspan(offset, size);
    }

    [[nodiscard]] std::expected<node_position, error>
    locate_address(const std::byte* pointer) const noexcept {
        if (pointer == nullptr) {
            return std::unexpected(error::invalid_block);
        }
        const auto base = reinterpret_cast<std::uintptr_t>(backing_.data());
        const auto address = reinterpret_cast<std::uintptr_t>(pointer);
        if (address < base || address - base >= header_->memory_size) {
            return std::unexpected(error::invalid_block);
        }
        const size_type offset = static_cast<size_type>(address - base);
        if (offset % header_->minimum_block_size != 0) {
            return std::unexpected(error::invalid_block);
        }

        node_position position = root_position();
        size_type node_begin = 0;
        size_type length = header_->tree_capacity;
        for (;;) {
            const size_type status = read_status(position);
            if (status == 0) {
                return std::unexpected(error::invalid_block);
            }
            const bool atomic_full = status == local_width(position) &&
                (position.depth == header_->order ||
                 (!compare_status(child_internal(position, false), 1) &&
                  !compare_status(child_internal(position, true), 1)));
            if (atomic_full) {
                if (node_begin == offset) {
                    return position;
                }
                return std::unexpected(error::invalid_block);
            }
            if (position.depth == header_->order) {
                return std::unexpected(error::invalid_block);
            }
            const size_type half = length / 2;
            if (offset < node_begin + half) {
                position = left_child(position);
            } else {
                position = right_child(position);
                node_begin += half;
            }
            length = half;
        }
    }

    [[nodiscard]] std::expected<block_location, error> locate(block_type block) const noexcept {
        if (block.empty() || block.data() == nullptr) {
            return std::unexpected(error::invalid_block);
        }
        const auto base = reinterpret_cast<std::uintptr_t>(backing_.data());
        const auto address = reinterpret_cast<std::uintptr_t>(block.data());
        if (address < base || address - base >= header_->memory_size) {
            return std::unexpected(error::invalid_block);
        }

        const size_type offset = static_cast<size_type>(address - base);
        const size_type minimum = header_->minimum_block_size;
        if (offset % minimum != 0 || block.size() < minimum ||
            block.size() > header_->tree_capacity ||
            block.size() % minimum != 0) {
            return std::unexpected(error::invalid_block);
        }
        const size_type block_units = block.size() / minimum;
        if (!std::has_single_bit(block_units) || offset % block.size() != 0 ||
            block.size() > header_->memory_size - offset) {
            return std::unexpected(error::invalid_block);
        }

        // A span carries its block size, so locate the node directly rather
        // than walking the tree from root or leaf on every free/reallocate.
        const size_type depth = header_->order -
            static_cast<size_type>(std::countr_zero(block_units));
        const node_position position{
            row_start({root_index, depth}) + offset / block.size(), depth
        };
        const size_type width = local_width(position);
        if (read_status(position) != width) {
            return std::unexpected(error::invalid_block);
        }
        if (depth < header_->order &&
            (compare_status(child_internal(position, false), 1) ||
             compare_status(child_internal(position, true), 1))) {
            return std::unexpected(error::invalid_block);
        }
        return block_location{position, offset, block.size()};
    }

    void shrink_in_place(node_position position, size_type current_size,
                         size_type target_size) noexcept {
        while (current_size > target_size) {
            const node_position left = left_child(position);
            const node_position right = right_child(position);
            write_status(right, 0);
            occupy_node(left);
            position = left;
            current_size /= 2;
        }
    }

    [[nodiscard]] bool grow_in_place(node_position position, size_type current_size,
                                     size_type target_size) noexcept {
        node_position expanded = position;
        size_type expanded_size = current_size;
        while (expanded_size < target_size) {
            // A right child cannot preserve its address when merged with its buddy.
            if (expanded.index == root_index || (expanded.index & 1u) != 0) {
                return false;
            }
            const node_position right_buddy = sibling(expanded);
            if (compare_status(internal(right_buddy), 1)) {
                return false;
            }
            expanded = parent(expanded);
            expanded_size *= 2;
        }
        occupy_node_clearing_descendants(expanded);
        return true;
    }

    [[nodiscard]] std::expected<void, error>
    mark_existing_allocation(size_type offset, size_type block_size) noexcept {
        if (block_size < header_->minimum_block_size ||
            block_size > header_->tree_capacity ||
            block_size % header_->minimum_block_size != 0 ||
            !std::has_single_bit(block_size / header_->minimum_block_size) ||
            offset % block_size != 0 || offset > header_->memory_size ||
            block_size > header_->memory_size - offset) {
            return std::unexpected(error::invalid_block);
        }
        if (!range_is_free(offset, block_size)) {
            return std::unexpected(error::range_conflict);
        }
        const size_type block_units = block_size / header_->minimum_block_size;
        const size_type depth = header_->order -
            static_cast<size_type>(std::countr_zero(block_units));
        const node_position position{
            row_start({root_index, depth}) + offset / block_size, depth
        };
        if (!valid(position) || node_offset(position) != offset ||
            node_size(position) != block_size || block_size > header_->free_size) {
            return std::unexpected(error::corrupted_metadata);
        }
        occupy_node(position);
        header_->free_size -= block_size;
        return {};
    }

    [[nodiscard]] bool range_is_free(size_type offset, size_type length) const noexcept {
        if (length == 0 || offset > header_->tree_capacity ||
            length > header_->tree_capacity - offset) {
            return false;
        }
        return range_is_free_node(root_position(), 0, header_->tree_capacity,
                                  offset, offset + length);
    }

    [[nodiscard]] bool range_is_free_node(node_position position, size_type node_begin,
                                          size_type node_length, size_type query_begin,
                                          size_type query_end) const noexcept {
        const size_type node_end = node_begin + node_length;
        if (query_end <= node_begin || query_begin >= node_end) {
            return true;
        }
        const size_type status = read_status(position);
        if (status == 0) {
            return true;
        }
        if (status == local_width(position) || position.depth == header_->order) {
            return false;
        }
        const size_type half = node_length / 2;
        return range_is_free_node(left_child(position), node_begin, half,
                                  query_begin, query_end) &&
               range_is_free_node(right_child(position), node_begin + half, half,
                                  query_begin, query_end);
    }

    void toggle_range(size_type offset, size_type length, bool mark) noexcept {
        if (length == 0) {
            return;
        }
        toggle_range_node(root_position(), 0, header_->tree_capacity,
                          offset, offset + length, mark);
    }

    void toggle_range_node(node_position position, size_type node_begin,
                           size_type node_length, size_type query_begin,
                           size_type query_end, bool mark) noexcept {
        const size_type node_end = node_begin + node_length;
        if (query_end <= node_begin || query_begin >= node_end) {
            return;
        }
        if (query_begin <= node_begin && node_end <= query_end) {
            if (mark) {
                // mark=true is used only for ranges already proven free
                // (reserve_range, shrinking resize, and initial inactive tail).
                occupy_node(position);
            } else {
                // A released range node becomes wholly free. Discard its old
                // descendants locally so the tree remains canonical.
                clear_descendant_bits(position);
                release_node(position);
            }
            return;
        }
        if (position.depth == header_->order) {
            return;
        }

        // A zero summary means this whole subtree is free. Its descendants
        // are canonical zeros; clear the immediate child summaries before
        // descending so a newly marked subrange cannot inherit old state.
        if (read_status(position) == 0) {
            if (!mark) {
                return;
            }
            write_status(left_child(position), 0);
            write_status(right_child(position), 0);
        }

        if (!mark && read_status(position) == local_width(position) &&
            !compare_status(child_internal(position, false), 1) &&
            !compare_status(child_internal(position, true), 1)) {
            // Split one larger reservation/allocation into two occupied buddies
            // before releasing only the requested half.
            occupy_node(left_child(position));
            occupy_node(right_child(position));
        }
        const size_type half = node_length / 2;
        toggle_range_node(left_child(position), node_begin, half,
                          query_begin, query_end, mark);
        toggle_range_node(right_child(position), node_begin + half, half,
                          query_begin, query_end, mark);
    }

    [[nodiscard]] std::expected<std::pair<size_type, size_type>, error>
    normalize_range(block_type requested) const noexcept {
        if (requested.empty() || requested.data() == nullptr) {
            return std::unexpected(error::invalid_size);
        }
        const auto base = reinterpret_cast<std::uintptr_t>(backing_.data());
        const auto address = reinterpret_cast<std::uintptr_t>(requested.data());
        if (address < base || address - base >= header_->memory_size) {
            return std::unexpected(error::invalid_block);
        }
        const size_type offset = static_cast<size_type>(address - base);
        if (offset % header_->minimum_block_size != 0) {
            return std::unexpected(error::invalid_alignment);
        }
        const size_type remaining = header_->memory_size - offset;
        if (requested.size() > remaining) {
            return std::unexpected(error::invalid_size);
        }
        const size_type alignment = header_->minimum_block_size;
        const size_type block_count = requested.size() / alignment +
            static_cast<size_type>((requested.size() % alignment) != 0);
        if (block_count > std::numeric_limits<size_type>::max() / alignment) {
            return std::unexpected(error::invalid_size);
        }
        const size_type rounded_size = block_count * alignment;
        if (rounded_size == 0 || rounded_size > remaining) {
            return std::unexpected(error::invalid_size);
        }
        return std::pair{offset, rounded_size};
    }

    [[nodiscard]] static constexpr std::uint64_t low_bits_mask(size_type count) noexcept {
        return count == word_bits ? std::numeric_limits<std::uint64_t>::max()
                                  : ((std::uint64_t{1} << count) - 1);
    }

    void set_reservation_bits(size_type first, size_type count, bool value) noexcept {
        while (count != 0) {
            const size_type bit_offset = first % word_bits;
            const size_type chunk = std::min(count, word_bits - bit_offset);
            const std::uint64_t mask = low_bits_mask(chunk) << bit_offset;
            auto& word = reservations_[first / word_bits];
            if (value) {
                word |= mask;
            } else {
                word &= ~mask;
            }
            first += chunk;
            count -= chunk;
        }
    }

    [[nodiscard]] bool reservation_range_is_set(size_type first, size_type count) const noexcept {
        while (count != 0) {
            const size_type bit_offset = first % word_bits;
            const size_type chunk = std::min(count, word_bits - bit_offset);
            const std::uint64_t mask = low_bits_mask(chunk) << bit_offset;
            if ((reservations_[first / word_bits] & mask) != mask) {
                return false;
            }
            first += chunk;
            count -= chunk;
        }
        return true;
    }

    [[nodiscard]] bool range_has_reservations(size_type offset, size_type length) const noexcept {
        if (header_->reserved_size == 0) {
            return false;
        }
        size_type first = offset / header_->minimum_block_size;
        size_type count = length / header_->minimum_block_size;
        while (count != 0) {
            const size_type bit_offset = first % word_bits;
            const size_type chunk = std::min(count, word_bits - bit_offset);
            const std::uint64_t mask = low_bits_mask(chunk) << bit_offset;
            if ((reservations_[first / word_bits] & mask) != 0) {
                return true;
            }
            first += chunk;
            count -= chunk;
        }
        return false;
    }

    [[nodiscard]] bool node_is_fully_reserved(node_position position) const noexcept {
        const size_type first = node_offset(position) / header_->minimum_block_size;
        const size_type count = node_size(position) / header_->minimum_block_size;
        return reservation_range_is_set(first, count);
    }

    // Fragmentation only needs free intervals. Fully occupied subtrees can
    // be skipped immediately; unlike walk(), there is no need to classify or
    // descend through the individual allocated/reserved blocks.
    void collect_free_squared_units(node_position position, size_type offset,
                                    size_type length, size_type& squared_sum) const noexcept {
        if (offset >= header_->memory_size) {
            return;
        }
        const size_type status = read_status(position);
        const size_type width = local_width(position);
        if (status == 0 && length <= header_->memory_size - offset) {
            const size_type units = length / header_->minimum_block_size;
            squared_sum += units * units;
            return;
        }
        if (status == width || position.depth == header_->order) {
            return;
        }
        const size_type half = length / 2;
        collect_free_squared_units(left_child(position), offset, half, squared_sum);
        collect_free_squared_units(right_child(position), offset + half, half, squared_sum);
    }

    template <class Visitor>
    [[nodiscard]] bool visit_node(node_position position, size_type offset,
                                  size_type length, Visitor&& visitor) const {
        if (offset >= header_->memory_size) {
            return true;
        }
        const size_type status = read_status(position);
        const size_type width = local_width(position);
        const bool fully_inside = length <= header_->memory_size - offset;
        if (fully_inside && status == 0) {
            return static_cast<bool>(std::invoke(visitor,
                block_info{backing_.subspan(offset, length), block_kind::free}));
        }
        if (fully_inside && status == width) {
            if (position.depth == header_->order ||
                !compare_status(child_internal(position, false), 1)) {
                const block_kind kind = node_is_fully_reserved(position)
                    ? block_kind::reserved : block_kind::allocated;
                return static_cast<bool>(std::invoke(visitor,
                    block_info{backing_.subspan(offset, length), kind}));
            }
        }
        if (position.depth == header_->order) {
            return true;
        }
        const size_type half = length / 2;
        return visit_node(left_child(position), offset, half, visitor) &&
               visit_node(right_child(position), offset + half, half, visitor);
    }

    block_type backing_{};
    std::span<std::byte> metadata_{};
    metadata_header* header_{};
    std::span<std::byte> tree_bits_{};
    std::span<std::uint64_t> reservations_{};
    std::span<const size_type> size_table_{};
    size_type minimum_shift_{};
};

} // namespace buddy
