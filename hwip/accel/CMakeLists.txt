# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.25)
project(deepspan-accel VERSION 1.0.0 LANGUAGES CXX)

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
        ${CMAKE_CURRENT_SOURCE_DIR}/gen/l3-cpp
)
add_dependencies(deepspan-accel-hw-model accel-codegen)

# ── Tests ─────────────────────────────────────────────────────────────────────
if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()
