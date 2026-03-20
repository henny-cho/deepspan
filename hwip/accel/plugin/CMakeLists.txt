# SPDX-License-Identifier: Apache-2.0
# hwip/accel/plugin/CMakeLists.txt — accel HWIP plugin shared library (C++20)

add_library(hwip_accel SHARED
    accel_plugin.cpp
    register.cpp
)

target_compile_features(hwip_accel PRIVATE cxx_std_20)

target_include_directories(hwip_accel
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${CMAKE_SOURCE_DIR}/server/include"
        # Generated per-hwip headers (rpc opcodes, etc.)
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/rpc"
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/sim"
)

target_link_libraries(hwip_accel
    PRIVATE
        deepspan-appframework
        deepspan-userlib
        spdlog::spdlog
)

set_target_properties(hwip_accel PROPERTIES
    OUTPUT_NAME "hwip_accel"
    VERSION "${PROJECT_VERSION}"
    SOVERSION "${PROJECT_VERSION_MAJOR}"
)

install(TARGETS hwip_accel
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
