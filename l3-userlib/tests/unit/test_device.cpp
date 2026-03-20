// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// test_device.cpp — Unit tests for DeepspanDevice.

#include <gtest/gtest.h>

#include <fcntl.h>       // access()
#include <unistd.h>

#include "deepspan/userlib/device.hpp"
#include "deepspan/userlib/error.hpp"

// Pull in the UAPI version macros for the compile-time check.
// The kernel include path is added via CMakeLists.txt.
#include <linux/deepspan.h> // NOLINT(hicpp-deprecated-headers)

namespace deepspan::userlib {

// ---------------------------------------------------------------------------
// TEST: opening a path that does not exist returns DeviceOpenFailed
// ---------------------------------------------------------------------------

TEST(DeepspanDevice, OpenNonexistentDeviceReturnsError) {  // NOLINT
    auto result = DeepspanDevice::open("/dev/deepspan_nonexistent_xxxx");
    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), Error::DeviceOpenFailed);
}

// ---------------------------------------------------------------------------
// TEST: move constructor transfers the fd; the moved-from object is invalid
// ---------------------------------------------------------------------------

TEST(DeepspanDevice, MoveSemantics) {  // NOLINT
    // Skip if /dev/hwip0 is not present on this machine.
    if (::access("/dev/hwip0", F_OK) != 0) {
        GTEST_SKIP() << "/dev/hwip0 not available; skipping move-semantics test";
    }

    auto result = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(result.has_value()) << "open failed: "
                                    << to_string(result.error());

    const int original_fd = result->fd();
    EXPECT_GE(original_fd, 0);

    // Move-construct.
    DeepspanDevice moved{std::move(*result)};
    EXPECT_EQ(moved.fd(), original_fd);

    // The moved-from object should no longer hold a valid fd.
    EXPECT_EQ(result->fd(), -1);  // NOLINT(bugprone-use-after-move)

    // Move-assign.
    auto result2 = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(result2.has_value());
    const int fd2 = result2->fd();

    moved = std::move(*result2);
    EXPECT_EQ(moved.fd(), fd2);
    EXPECT_EQ(result2->fd(), -1);  // NOLINT(bugprone-use-after-move)
}

// ---------------------------------------------------------------------------
// TEST: compile-time check that DEEPSPAN_UAPI_VERSION >= DEEPSPAN_UAPI_VERSION_MIN
// ---------------------------------------------------------------------------

TEST(DeepspanDevice, VersionCheckMacros) {  // NOLINT
    static_assert(DEEPSPAN_UAPI_VERSION >= DEEPSPAN_UAPI_VERSION_MIN,
                  "DEEPSPAN_UAPI_VERSION must be >= DEEPSPAN_UAPI_VERSION_MIN");

    // Runtime reflection of the same invariant (always passes if the
    // static_assert above compiles).
    EXPECT_GE(static_cast<unsigned>(DEEPSPAN_UAPI_VERSION),
              static_cast<unsigned>(DEEPSPAN_UAPI_VERSION_MIN));
}

} // namespace deepspan::userlib
