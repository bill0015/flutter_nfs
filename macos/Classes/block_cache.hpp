#ifndef BLOCK_CACHE_HPP
#define BLOCK_CACHE_HPP

#include <stdint.h>
#include <stddef.h>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <memory>
#include <condition_variable>

// 128KB Block Size
constexpr size_t BLOCK_SIZE = 128 * 1024;

// Ring Buffer Cache
class BlockCache {
public:
    static BlockCache& instance();

    void init(size_t capacity_mb);
    
    // Copy data from cache to output buffer.
    // Returns bytes read if some blocks are present.
    // Returns -1 if any blocks are missing and we should wait.
    // out_actual_len: actually copied bytes if partial is okay.
    int read(uint64_t offset, size_t len, uint8_t* out_buffer, size_t* out_actual_len = nullptr);

    // Get direct pointer to a block (for single block reads/fills)
    // Be careful with lifetime.
    uint8_t* get_block_ptr(uint64_t block_id);

    // Put data into a specific block
    void put_block(uint64_t block_id, const uint8_t* data, size_t len);

    // Invalidate a block (e.g. after write)
    void invalidate_block(uint64_t block_id);

    // Wait for a block to become available or timeout
    bool wait_for_block(uint64_t block_id, int timeout_ms);

private:
    BlockCache() = default;

    struct Slot {
        uint8_t data[BLOCK_SIZE];
        uint64_t block_id = 0;
        bool valid = false;
        uint64_t last_access = 0;
    };

    std::vector<std::unique_ptr<Slot>> slots_;
    std::unordered_map<uint64_t, int> id_to_slot_; // block_id -> slot_index
    std::mutex mutex_;
    std::condition_variable cv_;
    std::mutex cv_mutex_; // Dedicated mutex for CV if needed, but we can reuse mutex_
    size_t capacity_slots_ = 0;
    uint64_t access_counter_ = 0;

    int evict_lru();
};

extern "C" {
    void cache_init(int capacity_mb); // e.g. 64 or 128
    int cache_read(uint64_t offset, int len, uint8_t* out_ptr);
    void cache_put(uint64_t block_id, const uint8_t* data, int len);
    // Check if block exists (to decide whether to fetch)
    int cache_has_block(uint64_t block_id);
}

#endif // BLOCK_CACHE_HPP
