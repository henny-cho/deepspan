# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Deepspan Project Authors

cmake_minimum_required(VERSION 3.25)

# ---------------------------------------------------------------------------
# GoogleTest
# ---------------------------------------------------------------------------
if(DEEPSPAN_USE_SYSTEM_DEPS)
    find_package(GTest REQUIRED)
else()
    if(NOT TARGET gtest)
        add_subdirectory(${PROJECT_SOURCE_DIR}/../../third_party/googletest
                         ${CMAKE_CURRENT_BINARY_DIR}/googletest)
    endif()
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
add_executable(deepspan-appframework-tests
    unit/test_circuit_breaker.cpp
    unit/test_device_pool.cpp
    unit/test_session_manager.cpp
)

target_link_libraries(deepspan-appframework-tests
    PRIVATE
        deepspan-appframework
        GTest::gtest_main
)

target_compile_features(deepspan-appframework-tests PRIVATE cxx_std_20)

target_compile_options(deepspan-appframework-tests PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wno-unused-parameter
)

# ---------------------------------------------------------------------------
# Test discovery
# ---------------------------------------------------------------------------
gtest_discover_tests(deepspan-appframework-tests)
