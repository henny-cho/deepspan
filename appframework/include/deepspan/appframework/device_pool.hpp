// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// device_pool.hpp — Thread-safe pool of DeepspanDevice handles.
#pragma once
#include <deepspan/userlib/device.hpp>
#include <deepspan/userlib/error.hpp>
#include <deepspan/userlib/async_client.hpp>
#include <etl/expected.h>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace deepspan::appframework {

// DevicePool: pool of /dev/hwip* device handles
// Usage example:
//   auto pool = DevicePool::create({"/dev/hwip0", "/dev/hwip1"});
//   auto guard = pool->acquire();  // RAII — returns handle on destruction
//   guard->submit(req, user_data);
class DevicePool {
public:
    struct Entry {
        deepspan::userlib::DeepspanDevice device;
        deepspan::userlib::AsyncClient    client;
        bool in_use{false};
    };

    // RAII guard returned by acquire()
    class Guard {
    public:
        Guard() = default;
        ~Guard();
        Guard(const Guard&) = delete;
        Guard& operator=(const Guard&) = delete;
        Guard(Guard&&) noexcept;
        Guard& operator=(Guard&&) noexcept;

        deepspan::userlib::AsyncClient* operator->() noexcept { return &entry_->client; }
        deepspan::userlib::AsyncClient& operator*() noexcept  { return entry_->client; }
        bool valid() const noexcept { return entry_ != nullptr; }

    private:
        friend class DevicePool;
        Guard(DevicePool* pool, Entry* entry);
        DevicePool* pool_{nullptr};
        Entry* entry_{nullptr};
    };

    static etl::expected<std::unique_ptr<DevicePool>, deepspan::userlib::Error>
        create(std::vector<std::string> device_paths, unsigned uring_queue_depth = 64);

    // acquire(): returns an idle Entry. Returns Error::DeviceOpenFailed if all are in use.
    etl::expected<Guard, deepspan::userlib::Error> acquire();

    std::size_t size()     const noexcept;
    std::size_t in_use()   const noexcept;

private:
    explicit DevicePool(std::vector<Entry> entries);
    void release(Entry* entry);

    mutable std::mutex mu_;
    std::vector<Entry> entries_;
};

} // namespace deepspan::appframework
