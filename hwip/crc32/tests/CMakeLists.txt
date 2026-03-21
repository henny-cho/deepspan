# SPDX-License-Identifier: Apache-2.0
# hwip/crc32/tests — C++ E2E integration tests for the crc32 HWIP plugin.

find_package(GTest QUIET)
if(NOT TARGET GTest::gtest_main)
    message(STATUS "hwip/crc32/tests: GTest not found — skipping crc32_e2e_tests")
    return()
endif()

add_executable(crc32_e2e_tests
    test_crc32_e2e.cpp
)

target_compile_features(crc32_e2e_tests PRIVATE cxx_std_20)

target_include_directories(crc32_e2e_tests
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/../plugin"
        "${CMAKE_SOURCE_DIR}/server/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/sim"
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/rpc"
)

target_link_libraries(crc32_e2e_tests
    PRIVATE
        hwip_crc32_core          # static: Crc32Plugin without HwipRegistry
        deepspan-crc32-hw-model  # static: deepspan_crc32_dispatch + set_shm_base
        deepspan_hw_model        # platform hw-model server
        GTest::gtest_main
        rt
)

include(GoogleTest)
gtest_discover_tests(crc32_e2e_tests
    PROPERTIES
        TIMEOUT 30
        RUN_SERIAL TRUE   # tests share /deepspan_hwip_1 SHM — must not run in parallel
)
