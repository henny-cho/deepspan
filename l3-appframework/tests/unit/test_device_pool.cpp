// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// test_device_pool.cpp — Unit tests for DevicePool.

#include <gtest/gtest.h>

#include <deepspan/appframework/device_pool.hpp>
#include <deepspan/userlib/error.hpp>

namespace deepspan::appframework {

// ---------------------------------------------------------------------------
// TEST: create() with a non-existent device path returns an error
// ---------------------------------------------------------------------------

TEST(DevicePool, CreateFailsWithNonexistentPaths) {  // NOLINT
    auto result = DevicePool::create({"/dev/deepspan_nosuchdev"});
    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), deepspan::userlib::Error::DeviceOpenFailed);
}

// ---------------------------------------------------------------------------
// TEST: create() with an empty path list succeeds, pool size is 0
// ---------------------------------------------------------------------------

TEST(DevicePool, AcquireReturnsInvalidWithEmptyPaths) {  // NOLINT
    auto result = DevicePool::create({});
    ASSERT_TRUE(result.has_value());

    auto& pool = result.value();
    EXPECT_EQ(pool->size(), 0u);
    EXPECT_EQ(pool->in_use(), 0u);

    // acquire() on an empty pool should return an error.
    auto guard_result = pool->acquire();
    ASSERT_FALSE(guard_result.has_value());
    EXPECT_EQ(guard_result.error(), deepspan::userlib::Error::DeviceOpenFailed);
}

} // namespace deepspan::appframework
