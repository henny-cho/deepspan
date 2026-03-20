# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Deepspan Project Authors

cmake_minimum_required(VERSION 3.25)

# ---------------------------------------------------------------------------
# GoogleTest
# ---------------------------------------------------------------------------
if(DEEPSPAN_USE_SYSTEM_DEPS)
    find_package(GTest REQUIRED)
else()
    # Use vendored copy.
    if(NOT TARGET gtest)
        add_subdirectory(${PROJECT_SOURCE_DIR}/../../third_party/googletest
                         ${CMAKE_CURRENT_BINARY_DIR}/googletest)
    endif()
    # Create the GTest::gtest_main alias if the vendored build doesn't provide it.
    if(TARGET gtest_main AND NOT TARGET GTest::gtest_main)
        add_library(GTest::gtest_main ALIAS gtest_main)
    endif()
    if(TARGET gtest AND NOT TARGET GTest::gtest)
        add_library(GTest::gtest ALIAS gtest)
    endif()
endif()

include(GoogleTest)

# ---------------------------------------------------------------------------
# Test executable
# ---------------------------------------------------------------------------
add_executable(deepspan-userlib-tests
    unit/test_device.cpp
    unit/test_async_client.cpp
    integration/test_device_integration.cpp
)

target_link_libraries(deepspan-userlib-tests
    PRIVATE
        deepspan-userlib
        GTest::gtest_main
)

# Test files include <linux/deepspan.h> which lives in the kernel UAPI tree.
target_include_directories(deepspan-userlib-tests PRIVATE
    ${PROJECT_SOURCE_DIR}/../../l2/kernel/include/uapi
)

target_compile_features(deepspan-userlib-tests PRIVATE cxx_std_23)

target_compile_options(deepspan-userlib-tests PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wno-unused-parameter
)

# ---------------------------------------------------------------------------
# Test discovery
# ---------------------------------------------------------------------------
gtest_discover_tests(deepspan-userlib-tests)
