// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// test_session_manager.cpp — Unit tests for SessionManager.

#include <gtest/gtest.h>

#include <deepspan/appframework/session_manager.hpp>
#include <deepspan/userlib/error.hpp>

namespace deepspan::appframework {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static SessionManager::Config make_cfg(std::vector<std::string> paths = {},
                                       uint32_t failure_threshold = 3) {
    SessionManager::Config cfg;
    cfg.device_paths       = std::move(paths);
    cfg.uring_queue_depth  = 64;
    cfg.cb_config.failure_threshold = failure_threshold;
    cfg.cb_config.success_threshold = 2;
    cfg.cb_config.open_duration     = std::chrono::milliseconds{5000};
    cfg.cb_config.name              = "test-sm";
    return cfg;
}

// ---------------------------------------------------------------------------
// TEST: create() with a bad device path propagates DevicePool error
// ---------------------------------------------------------------------------

TEST(SessionManager, CreateFailsWithBadDevicePath) {  // NOLINT
    auto result = SessionManager::create(make_cfg({"/dev/deepspan_nosuchdev"}));
    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), deepspan::userlib::Error::DeviceOpenFailed);
}

// ---------------------------------------------------------------------------
// TEST: create() with empty paths succeeds
// ---------------------------------------------------------------------------

TEST(SessionManager, CreateSucceedsWithEmptyPaths) {  // NOLINT
    auto result = SessionManager::create(make_cfg({}));
    EXPECT_TRUE(result.has_value());
}

// ---------------------------------------------------------------------------
// TEST: circuit_state() starts in Closed state
// ---------------------------------------------------------------------------

TEST(SessionManager, CircuitStateStartsClosed) {  // NOLINT
    auto sm = SessionManager::create(make_cfg({}));
    ASSERT_TRUE(sm.has_value());
    EXPECT_EQ(sm->circuit_state(), CircuitBreaker::State::Closed);
}

// ---------------------------------------------------------------------------
// TEST: execute() on empty pool returns SubmitFailed
// ---------------------------------------------------------------------------

TEST(SessionManager, ExecuteFailsWhenPoolEmpty) {  // NOLINT
    auto sm = SessionManager::create(make_cfg({}));
    ASSERT_TRUE(sm.has_value());

    bool f_called = false;
    auto result = sm->execute([&](deepspan::userlib::AsyncClient&) {
        f_called = true;
        return true;
    });

    EXPECT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), deepspan::userlib::Error::SubmitFailed);
    // acquire() failed before f was reached
    EXPECT_FALSE(f_called);
}

// ---------------------------------------------------------------------------
// TEST: circuit opens after failure_threshold consecutive acquire failures
// ---------------------------------------------------------------------------

TEST(SessionManager, CircuitOpensAfterThresholdFailures) {  // NOLINT
    auto sm = SessionManager::create(make_cfg({}, /*failure_threshold=*/3));
    ASSERT_TRUE(sm.has_value());

    // Each execute() with an empty pool: acquire() fails → CB records failure.
    for (int i = 0; i < 3; ++i) {
        sm->execute([](deepspan::userlib::AsyncClient&) { return true; });
    }

    EXPECT_EQ(sm->circuit_state(), CircuitBreaker::State::Open);
}

// ---------------------------------------------------------------------------
// TEST: execute() is blocked (without calling f) when circuit is Open
// ---------------------------------------------------------------------------

TEST(SessionManager, ExecuteBlockedWhenCircuitOpen) {  // NOLINT
    auto sm = SessionManager::create(make_cfg({}, /*failure_threshold=*/3));
    ASSERT_TRUE(sm.has_value());

    // Trip the breaker.
    for (int i = 0; i < 3; ++i) {
        sm->execute([](deepspan::userlib::AsyncClient&) { return true; });
    }
    ASSERT_EQ(sm->circuit_state(), CircuitBreaker::State::Open);

    // With circuit Open, f must not be called.
    bool f_called = false;
    auto result = sm->execute([&](deepspan::userlib::AsyncClient&) {
        f_called = true;
        return true;
    });

    EXPECT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), deepspan::userlib::Error::SubmitFailed);
    EXPECT_FALSE(f_called);
}

} // namespace deepspan::appframework
