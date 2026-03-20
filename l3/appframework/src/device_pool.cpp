// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// device_pool.cpp — Implementation of the DevicePool.

#include <deepspan/appframework/device_pool.hpp>

#include <utility>

namespace deepspan::appframework {

// ---------------------------------------------------------------------------
// DevicePool::Guard
// ---------------------------------------------------------------------------

DevicePool::Guard::Guard(DevicePool* pool, Entry* entry)
    : pool_(pool), entry_(entry)
{}

DevicePool::Guard::~Guard() {
    if (pool_ && entry_) {
        pool_->release(entry_);
    }
}

DevicePool::Guard::Guard(Guard&& other) noexcept
    : pool_(other.pool_), entry_(other.entry_)
{
    other.pool_  = nullptr;
    other.entry_ = nullptr;
}

DevicePool::Guard& DevicePool::Guard::operator=(Guard&& other) noexcept {
    if (this != &other) {
        // Release the currently held entry before taking the new one.
        if (pool_ && entry_) {
            pool_->release(entry_);
        }
        pool_  = other.pool_;
        entry_ = other.entry_;
        other.pool_  = nullptr;
        other.entry_ = nullptr;
    }
    return *this;
}

// ---------------------------------------------------------------------------
// DevicePool
// ---------------------------------------------------------------------------

DevicePool::DevicePool(std::vector<Entry> entries)
    : entries_(std::move(entries))
{}

/*static*/
std::expected<std::unique_ptr<DevicePool>, deepspan::userlib::Error>
DevicePool::create(std::vector<std::string> device_paths, unsigned uring_queue_depth) {
    std::vector<Entry> entries;
    entries.reserve(device_paths.size());

    for (const auto& path : device_paths) {
        // Open the device.
        auto dev_result = deepspan::userlib::DeepspanDevice::open(path);
        if (!dev_result.has_value()) {
            return std::unexpected(dev_result.error());
        }

        // Create the async client backed by the just-opened device.
        auto client_result = deepspan::userlib::AsyncClient::create(
            dev_result.value(), uring_queue_depth);
        if (!client_result.has_value()) {
            return std::unexpected(client_result.error());
        }

        entries.push_back(Entry{
            std::move(dev_result.value()),
            std::move(client_result.value()),
            /*in_use=*/false
        });
    }

    // Use new + unique_ptr because the constructor is private.
    // NOTE: After construction, entries_ is never resized; raw Entry* pointers
    // vended by acquire() remain stable for the lifetime of the DevicePool.
    return std::unique_ptr<DevicePool>(new DevicePool(std::move(entries)));
}

std::expected<DevicePool::Guard, deepspan::userlib::Error> DevicePool::acquire() {
    std::unique_lock<std::mutex> lock(mu_);

    for (auto& entry : entries_) {
        if (!entry.in_use) {
            entry.in_use = true;
            return Guard(this, &entry);
        }
    }

    return std::unexpected(deepspan::userlib::Error::DeviceOpenFailed);
}

std::size_t DevicePool::size() const noexcept {
    std::unique_lock<std::mutex> lock(mu_);
    return entries_.size();
}

std::size_t DevicePool::in_use() const noexcept {
    std::unique_lock<std::mutex> lock(mu_);
    std::size_t count = 0;
    for (const auto& entry : entries_) {
        if (entry.in_use) {
            ++count;
        }
    }
    return count;
}

void DevicePool::release(Entry* entry) {
    std::unique_lock<std::mutex> lock(mu_);
    if (entry) {
        entry->in_use = false;
    }
}

} // namespace deepspan::appframework
