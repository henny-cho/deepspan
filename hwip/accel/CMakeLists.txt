# SPDX-License-Identifier: Apache-2.0
# Included via add_subdirectory() from root CMakeLists.txt (dev-hwip preset).
# cmake/hwip-plugin.cmake must be included before this file.

# ── Codegen ─────────────────────────────────────────────────────────────────
deepspan_hwip_codegen(
    HWIP_TYPE   accel
    DESCRIPTOR  ${CMAKE_CURRENT_SOURCE_DIR}/hwip.yaml
    OUT_DIR     ${CMAKE_CURRENT_SOURCE_DIR}/gen
)

# ── HW model library ─────────────────────────────────────────────────────────
deepspan_hwip_target(
    NAME     deepspan-accel-hw-model
    HWIP_TYPE accel
    SOURCES
        hw-model/src/accel_hw_model.cpp
    INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/hw-model/include
        ${CMAKE_CURRENT_SOURCE_DIR}/gen/sim
        ${CMAKE_CURRENT_SOURCE_DIR}/gen/rpc
)
add_dependencies(deepspan-accel-hw-model accel-codegen)

# ── Submitter plugin (.so) ────────────────────────────────────────────────────
add_subdirectory(plugin)

# ── Tests ─────────────────────────────────────────────────────────────────────
if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()
