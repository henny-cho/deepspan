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
    add_subdirectory(${PROJECT_SOURCE_DIR}/../../third_party/googletest
                     ${CMAKE_CURRENT_BINARY_DIR}/googletest)
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
)

target_link_libraries(deepspan-userlib-tests
    PRIVATE
        deepspan-userlib
        GTest::gtest_main
)

target_compile_features(deepspan-userlib-tests PRIVATE cxx_std_20)

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
