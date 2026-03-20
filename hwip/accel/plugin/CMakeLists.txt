# SPDX-License-Identifier: Apache-2.0
# hwip/accel/plugin/CMakeLists.txt — accel HWIP plugin shared library (C++20)

# ── Common include paths shared by plugin .so and test static lib ────────────
set(_ACCEL_INCLUDES
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/server/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../gen/rpc"
    "${CMAKE_CURRENT_SOURCE_DIR}/../gen/sim"
)

# ── hwip_accel_core — static lib (accel_plugin.cpp only, no HwipRegistry) ───
# Used by tests that link directly without going through dlopen.
add_library(hwip_accel_core STATIC accel_plugin.cpp)
target_compile_features(hwip_accel_core PUBLIC cxx_std_20)
target_include_directories(hwip_accel_core PUBLIC ${_ACCEL_INCLUDES})
target_link_libraries(hwip_accel_core
    PUBLIC
        spdlog::spdlog
    PRIVATE
        deepspan-appframework
        deepspan-userlib
        rt
)

# ── hwip_accel — shared library (.so) loaded at runtime via dlopen ───────────
# register.cpp references HwipRegistry which is provided by the server
# executable at load time (hence ALLOW_SHLIB_UNDEFINED).
add_library(hwip_accel SHARED
    accel_plugin.cpp
    register.cpp
)

target_compile_features(hwip_accel PRIVATE cxx_std_20)
target_include_directories(hwip_accel PRIVATE ${_ACCEL_INCLUDES})
target_link_libraries(hwip_accel
    PRIVATE
        deepspan-appframework
        deepspan-userlib
        spdlog::spdlog
        rt
)

set_target_properties(hwip_accel PROPERTIES
    OUTPUT_NAME "hwip_accel"
    VERSION "${PROJECT_VERSION}"
    SOVERSION "${PROJECT_VERSION_MAJOR}"
    LINK_FLAGS "-Wl,--allow-shlib-undefined"
)

install(TARGETS hwip_accel
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
