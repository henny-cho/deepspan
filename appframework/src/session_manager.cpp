// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// session_manager.cpp — Implementation of SessionManager.

#include <deepspan/appframework/session_manager.hpp>

#include <memory>
#include <utility>

namespace deepspan::appframework {

SessionManager::SessionManager(std::unique_ptr<DevicePool> pool,
                               std::unique_ptr<CircuitBreaker> cb)
    : pool_(std::move(pool))
    , cb_(std::move(cb))
{}

/*static*/
std::expected<SessionManager, deepspan::userlib::Error>
SessionManager::create(Config cfg) {
    auto pool_result = DevicePool::create(
        std::move(cfg.device_paths), cfg.uring_queue_depth);
    if (!pool_result.has_value()) {
        return std::unexpected(pool_result.error());
    }

    auto cb = std::make_unique<CircuitBreaker>(std::move(cfg.cb_config));

    return SessionManager(std::move(pool_result.value()), std::move(cb));
}

std::expected<void, deepspan::userlib::Error>
SessionManager::execute(std::function<bool(deepspan::userlib::AsyncClient&)> f) {
    const bool ok = cb_->call([&]() -> bool {
        auto guard_result = pool_->acquire();
        if (!guard_result.has_value()) {
            return false;
        }
        return f(*guard_result.value());
    });

    if (!ok) {
        return std::unexpected(deepspan::userlib::Error::SubmitFailed);
    }
    return {};
}

CircuitBreaker::State SessionManager::circuit_state() const noexcept {
    return cb_->state();
}

} // namespace deepspan::appframework
