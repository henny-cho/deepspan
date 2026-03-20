# SPDX-License-Identifier: Apache-2.0
# hwip/testutils/CMakeLists.txt — C++20 gtest helpers shared across HWIP tests

if(NOT DEEPSPAN_BUILD_TESTS)
    return()
endif()

find_package(GTest REQUIRED)

add_library(hwip-testutils STATIC
    # TODO: add C++ test helper sources as they are created
    # e.g.: grpc_test_channel.cpp  stub_registry.cpp
)

target_compile_features(hwip-testutils PUBLIC cxx_std_20)

target_include_directories(hwip-testutils
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE
        "${CMAKE_SOURCE_DIR}/server/include"
)

target_link_libraries(hwip-testutils
    PUBLIC
        GTest::gtest
        deepspan-appframework
        deepspan-userlib
)
