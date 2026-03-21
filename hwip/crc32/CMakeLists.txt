# SPDX-License-Identifier: Apache-2.0
# Included via add_subdirectory() from root CMakeLists.txt (dev-crc32 preset).
# cmake/hwip-plugin.cmake must be included before this file.

# ── Codegen ─────────────────────────────────────────────────────────────────
deepspan_hwip_codegen(
    HWIP_TYPE   crc32
    DESCRIPTOR  ${CMAKE_CURRENT_SOURCE_DIR}/hwip.yaml
    OUT_DIR     ${CMAKE_CURRENT_SOURCE_DIR}/gen
)

# ── HW model library ─────────────────────────────────────────────────────────
deepspan_hwip_target(
    NAME     deepspan-crc32-hw-model
    HWIP_TYPE crc32
    SOURCES
        hw-model/src/crc32_hw_model.cpp
    INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/gen/sim
        ${CMAKE_CURRENT_SOURCE_DIR}/gen/rpc
)
add_dependencies(deepspan-crc32-hw-model crc32-codegen)

# ── Submitter plugin (.so) ────────────────────────────────────────────────────
add_subdirectory(plugin)

# ── Tests ─────────────────────────────────────────────────────────────────────
if(DEEPSPAN_BUILD_TESTS OR BUILD_TESTING)
    add_subdirectory(tests)
endif()
