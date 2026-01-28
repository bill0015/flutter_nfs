#include "block_cache.hpp"
#include <iostream>
#include <algorithm>
#include <cstring>

BlockCache& BlockCache::instance() {
    static BlockCache instance;
    return instance;
}

void BlockCache::init(size_t capacity_mb) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    // Default to 64MB if 0 passed
    if (capacity_mb <= 0) capacity_mb = 64;
    
    size_t new_slots = (capacity_mb * 1024 * 1024) / BLOCK_SIZE;
    
    if (slots_.empty()) {
        slots_.reserve(new_slots);
        for (size_t i = 0; i < new_slots; ++i) {
            slots_.push_back(std::make_unique<Slot>());
        }
        capacity_slots_ = new_slots;
         std::cout << "[BlockCache] Initialized with " << capacity_slots_ << " slots ("
                   << capacity_mb << " MB)" << std::endl;
    }
}

int BlockCache::evict_lru() {
    int victim_idx = -1;
    uint64_t min_access = UINT64_MAX;

    // 1. Look for invalid (empty) slots first
    for (size_t i = 0; i < slots_.size(); ++i) {
        if (!slots_[i]->valid) return i;
    }

    // 2. Find LRU
    for (size_t i = 0; i < slots_.size(); ++i) {
        if (slots_[i]->last_access < min_access) {
            min_access = slots_[i]->last_access;
            victim_idx = i;
        }
    }
    
    if (victim_idx != -1) {
        // Remove old mapping
        id_to_slot_.erase(slots_[victim_idx]->block_id);
        slots_[victim_idx]->valid = false;
    }
    return victim_idx;
}

void BlockCache::put_block(uint64_t block_id, const uint8_t* data, size_t len) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (id_to_slot_.count(block_id)) {
        // Block already present. We don't overwrite for performance
        // (assuming read-only ROM usage).
        return; 
    }

    int slot_idx = evict_lru();
    if (slot_idx == -1) {
        // Should happen only if capacity 0
        return; 
    }

    Slot* slot = slots_[slot_idx].get();
    size_t copy_len = std::min(len, BLOCK_SIZE);
    
    if (data != nullptr) {
        std::memcpy(slot->data, data, copy_len);
    }
    
    // Zero fill padding if short read
    if (copy_len < BLOCK_SIZE) {
        std::memset(slot->data + copy_len, 0, BLOCK_SIZE - copy_len);
    }
    
    slot->block_id = block_id;
    slot->valid = true;
    slot->last_access = ++access_counter_;
    
    id_to_slot_[block_id] = slot_idx;
    
    // Notify waiters
    cv_.notify_all();
}

void BlockCache::invalidate_block(uint64_t block_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = id_to_slot_.find(block_id);
    if (it != id_to_slot_.end()) {
        slots_[it->second]->valid = false;
        id_to_slot_.erase(it);
        std::cout << "[BlockCache] Invalidated block " << block_id << std::endl;
    }
}

bool BlockCache::wait_for_block(uint64_t block_id, int timeout_ms) {
    std::unique_lock<std::mutex> lock(mutex_);
    if (id_to_slot_.count(block_id)) return true;
    
    return cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms), [this, block_id]{
        return id_to_slot_.count(block_id) > 0;
    });
}

uint8_t* BlockCache::get_block_ptr(uint64_t block_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = id_to_slot_.find(block_id);
    if (it != id_to_slot_.end()) {
        Slot* slot = slots_[it->second].get();
        slot->last_access = ++access_counter_;
        return slot->data;
    }
    return nullptr;
}

int BlockCache::read(uint64_t offset, size_t len, uint8_t* out_buffer, size_t* out_actual_len) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (id_to_slot_.empty()) {
        return -1;
    }

    uint64_t start_block = offset / BLOCK_SIZE;
    uint64_t end_block = (offset + len - 1) / BLOCK_SIZE;
    size_t copied = 0;
    
    for (uint64_t b = start_block; b <= end_block; ++b) {
        auto it = id_to_slot_.find(b);
        if (it == id_to_slot_.end()) {
            // Missed a block. 
            // If we copied something already, that's a partial hit.
            // If we missed the VERY FIRST block, return -1.
            if (copied > 0) break;
            return -1; 
        }
        
        Slot* slot = slots_[it->second].get();
        slot->last_access = ++access_counter_;
        
        size_t block_offset = (b == start_block) ? (offset % BLOCK_SIZE) : 0;
        size_t available = BLOCK_SIZE - block_offset;
        size_t remaining_req = len - copied;
        size_t to_copy = std::min(available, remaining_req);
        
        if (out_buffer != nullptr) {
            std::memcpy(out_buffer + copied, slot->data + block_offset, to_copy);
        }
        copied += to_copy;
    }
    
    if (out_actual_len) *out_actual_len = copied;
    return static_cast<int>(copied);
}

// C API Implementation
#if defined(__APPLE__) || defined(__GNUC__)
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define EXPORT
#endif

extern "C" {
    EXPORT void cache_init(int capacity_mb) {
        BlockCache::instance().init(capacity_mb);
    }
    
    EXPORT int cache_read(uint64_t offset, int len, uint8_t* out_ptr) {
        return BlockCache::instance().read(offset, len, out_ptr);
    }
    
    EXPORT void cache_put(uint64_t block_id, const uint8_t* data, int len) {
        BlockCache::instance().put_block(block_id, data, len);
    }
    
    EXPORT int cache_has_block(uint64_t block_id) {
        return BlockCache::instance().get_block_ptr(block_id) != nullptr ? 1 : 0;
    }
    
    EXPORT int cache_get_block_size() {
        return static_cast<int>(BLOCK_SIZE);
    }
}
