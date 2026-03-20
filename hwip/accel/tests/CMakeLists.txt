# SPDX-License-Identifier: Apache-2.0
# hwip/accel/tests — C++ E2E integration tests for the accel HWIP plugin.

find_package(GTest QUIET)
if(NOT TARGET GTest::gtest_main)
    message(STATUS "hwip/accel/tests: GTest not found — skipping accel_e2e_tests")
    return()
endif()

add_executable(accel_e2e_tests
    test_accel_e2e.cpp
)

target_compile_features(accel_e2e_tests PRIVATE cxx_std_20)

target_include_directories(accel_e2e_tests
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/../plugin"
        "${CMAKE_SOURCE_DIR}/server/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/sim"
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/rpc"
)

target_link_libraries(accel_e2e_tests
    PRIVATE
        hwip_accel_core      # static: AccelPlugin without HwipRegistry
        deepspan_hw_model
        GTest::gtest_main
        rt
)

include(GoogleTest)
gtest_discover_tests(accel_e2e_tests
    PROPERTIES
        TIMEOUT 30
        RUN_SERIAL TRUE   # tests share /deepspan_hwip_0 SHM — must not run in parallel
)
