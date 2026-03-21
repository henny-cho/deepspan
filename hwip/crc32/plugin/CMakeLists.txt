# SPDX-License-Identifier: Apache-2.0
# hwip/crc32/plugin/CMakeLists.txt — CRC32 HWIP plugin shared library (C++20)

set(_CRC32_INCLUDES
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/server/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../gen/rpc"
    "${CMAKE_CURRENT_SOURCE_DIR}/../gen/sim"
)

# ── hwip_crc32_core — static lib (crc32_plugin.cpp only, no HwipRegistry) ───
# Used by tests that link directly without going through dlopen.
add_library(hwip_crc32_core STATIC crc32_plugin.cpp)
target_compile_features(hwip_crc32_core PUBLIC cxx_std_20)
target_include_directories(hwip_crc32_core PUBLIC ${_CRC32_INCLUDES})
target_link_libraries(hwip_crc32_core
    PUBLIC
        spdlog::spdlog
    PRIVATE
        deepspan-appframework
        deepspan-userlib
        rt
)

# ── hwip_crc32 — shared library (.so) loaded at runtime via dlopen ───────────
# register.cpp references HwipRegistry which is provided by the server
# executable at load time (hence ALLOW_SHLIB_UNDEFINED).
add_library(hwip_crc32 SHARED
    crc32_plugin.cpp
    register.cpp
)

target_compile_features(hwip_crc32 PRIVATE cxx_std_20)
target_include_directories(hwip_crc32 PRIVATE ${_CRC32_INCLUDES})
target_link_libraries(hwip_crc32
    PRIVATE
        deepspan-appframework
        deepspan-userlib
        spdlog::spdlog
        rt
)

set_target_properties(hwip_crc32 PROPERTIES
    OUTPUT_NAME "hwip_crc32"
    VERSION "${PROJECT_VERSION}"
    SOVERSION "${PROJECT_VERSION_MAJOR}"
    LINK_FLAGS "-Wl,--allow-shlib-undefined"
)

install(TARGETS hwip_crc32
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
