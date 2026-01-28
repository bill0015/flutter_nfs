#ifndef NFS_POOL_HPP
#define NFS_POOL_HPP

#include <nfsc/libnfs.h>
#include <string>
#include <unordered_map>
#include <mutex>
#include <memory>
#include <iostream>

class NfsPool {
public:
    static NfsPool& instance() {
        static NfsPool instance;
        return instance;
    }

    struct Connection {
        struct nfs_context* nfs;
        std::string server;
        std::string export_path;
        int ref_count;
        std::mutex context_mutex; 
        bool is_ready; // True if mount succeeded
    };

    struct ConnectionHandle {
        struct nfs_context* nfs;
        std::mutex* mutex;
    };

    ConnectionHandle acquire(const std::string& server, const std::string& export_path) {
        std::string key = server + ":" + export_path;
        
        {
            std::lock_guard<std::mutex> lock(pool_mutex_);
            if (pool_.count(key)) {
                auto& conn = pool_[key];
                conn->ref_count++;
                return {conn->nfs, &conn->context_mutex};
            }
        }

        std::cout << "[NfsPool] acquire: " << server << export_path << std::endl;
        
        // Not found, create new context WITHOUT holding global lock for potential blocking mount
        struct nfs_context* nfs = nfs_init_context();
        if (!nfs) return {nullptr, nullptr};

        std::cout << "[NfsPool] Calling nfs_mount for " << server << " " << export_path << std::endl;
        int ret = nfs_mount(nfs, server.c_str(), export_path.c_str());
        std::cout << "[NfsPool] nfs_mount status: " << ret << std::endl;
        
        {
            std::lock_guard<std::mutex> lock(pool_mutex_);
            // Double check if someone else mounted it while we were waiting
            if (pool_.count(key)) {
                nfs_destroy_context(nfs); // Dispose ours, use existing
                auto& conn = pool_[key];
                conn->ref_count++;
                return {conn->nfs, &conn->context_mutex};
            }

            if (ret != 0) {
                nfs_destroy_context(nfs);
                return {nullptr, nullptr};
            }

            auto conn = std::make_unique<Connection>();
            conn->nfs = nfs;
            conn->server = server;
            conn->export_path = export_path;
            conn->ref_count = 1;
            conn->is_ready = true;

            ConnectionHandle handle = {conn->nfs, &conn->context_mutex};
            pool_[key] = std::move(conn);
            std::cout << "[NfsPool] Created new connection for " << key << std::endl;
            return handle;
        }
    }

    void release(struct nfs_context* nfs) {
        std::lock_guard<std::mutex> lock(pool_mutex_);
        for (auto it = pool_.begin(); it != pool_.end(); ++it) {
            if (it->second->nfs == nfs) {
                it->second->ref_count--;
                // We keep them alive for the duration of the app for now. 
                return;
            }
        }
    }

private:
    NfsPool() = default;
    ~NfsPool() {
        // Global cleanup
        for (auto& pair : pool_) {
            if (pair.second->nfs) {
                nfs_umount(pair.second->nfs);
                nfs_destroy_context(pair.second->nfs);
            }
        }
    }

    std::unordered_map<std::string, std::unique_ptr<Connection>> pool_;
    std::mutex pool_mutex_;
};

#endif // NFS_POOL_HPP
