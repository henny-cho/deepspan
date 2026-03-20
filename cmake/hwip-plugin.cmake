# SPDX-License-Identifier: Apache-2.0
# hwip-plugin.cmake — CMake helpers for HWIP plugin repositories.
#
# Usage in HWIP repo CMakeLists.txt:
#   find_package(DeepspanPlatform REQUIRED ...)
#   include(DeepspanHwip)
#   deepspan_hwip_target(
#       NAME deepspan-accel-hw-model
#       HWIP_TYPE accel
#       SOURCES hw-model/src/reg_map.cpp
#   )

# Guard against multiple includes
include_guard(GLOBAL)

#
# deepspan_hwip_plugin(
#     NAME      <target-name>         # e.g. hwip_accel
#     HWIP_TYPE <hwip-type>           # e.g. accel, codec
#     SOURCES   <src...>
#     [INCLUDE_DIRS <dir...>]
#     [DEPS <dep...>]
# )
#
# Creates a C++20 SHARED library that implements deepspan::server::Submitter
# and self-registers via HwipRegistry at dlopen time.
#
function(deepspan_hwip_plugin)
    cmake_parse_arguments(HWIP "" "NAME;HWIP_TYPE" "SOURCES;INCLUDE_DIRS;DEPS" ${ARGN})

    if(NOT HWIP_NAME)
        message(FATAL_ERROR "deepspan_hwip_plugin: NAME is required")
    endif()
    if(NOT HWIP_HWIP_TYPE)
        message(FATAL_ERROR "deepspan_hwip_plugin: HWIP_TYPE is required")
    endif()
    if(NOT HWIP_SOURCES)
        message(FATAL_ERROR "deepspan_hwip_plugin: SOURCES is required")
    endif()

    add_library(${HWIP_NAME} SHARED ${HWIP_SOURCES})

    target_compile_features(${HWIP_NAME} PRIVATE cxx_std_20)
    target_compile_definitions(${HWIP_NAME} PRIVATE
        DEEPSPAN_HWIP_TYPE="${HWIP_HWIP_TYPE}"
    )

    # Standard include dirs: server interface + generated headers + caller-provided
    target_include_directories(${HWIP_NAME}
        PUBLIC
            "${CMAKE_CURRENT_SOURCE_DIR}/gen/sim"
            "${CMAKE_CURRENT_SOURCE_DIR}/gen/rpc"
            ${HWIP_INCLUDE_DIRS}
        PRIVATE
            "${CMAKE_SOURCE_DIR}/server/include"
    )

    target_link_libraries(${HWIP_NAME}
        PUBLIC
            deepspan-appframework
            deepspan-userlib
        PRIVATE
            spdlog::spdlog
            ${HWIP_DEPS}
    )

    set_target_properties(${HWIP_NAME} PROPERTIES
        OUTPUT_NAME "${HWIP_NAME}"
        VERSION "${PROJECT_VERSION}"
        SOVERSION "${PROJECT_VERSION_MAJOR}"
    )

    install(TARGETS ${HWIP_NAME}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    )
endfunction()

# Backward-compat alias (was deepspan_hwip_target in the old Go-era layout).
function(deepspan_hwip_target)
    deepspan_hwip_plugin(${ARGN})
endfunction()

#
# deepspan_hwip_codegen(
#     HWIP_TYPE   <hwip-type>
#     DESCRIPTOR  <path-to-hwip.yaml>
#     OUT_DIR     <output-dir>
#     [TARGETS    all|kernel|firmware|sim|rpc|proto|python]
# )
#
# Adds a custom_target that runs deepspan-codegen to regenerate artifacts
# from hwip.yaml. Generated subdirs: gen/{kernel,firmware,sim,rpc,proto,sdk}/
# (gen/go/ is no longer produced).
#
function(deepspan_hwip_codegen)
    cmake_parse_arguments(CG "" "HWIP_TYPE;DESCRIPTOR;OUT_DIR;TARGETS" "" ${ARGN})

    if(NOT CG_HWIP_TYPE)
        message(FATAL_ERROR "deepspan_hwip_codegen: HWIP_TYPE is required")
    endif()
    if(NOT CG_DESCRIPTOR)
        set(CG_DESCRIPTOR "${CMAKE_CURRENT_SOURCE_DIR}/hwip.yaml")
    endif()
    if(NOT CG_OUT_DIR)
        set(CG_OUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/gen")
    endif()
    if(NOT CG_TARGETS)
        set(CG_TARGETS "all")
    endif()

    find_package(Python3 REQUIRED COMPONENTS Interpreter)

    set(_stamp "${CMAKE_CURRENT_BINARY_DIR}/${CG_HWIP_TYPE}-codegen.stamp")

    add_custom_command(
        OUTPUT ${_stamp}
        COMMAND ${Python3_EXECUTABLE} -m deepspan_codegen
            --descriptor ${CG_DESCRIPTOR}
            --out ${CG_OUT_DIR}
            --target ${CG_TARGETS}
        COMMAND ${CMAKE_COMMAND} -E touch ${_stamp}
        DEPENDS ${CG_DESCRIPTOR}
        COMMENT "deepspan-codegen: ${CG_HWIP_TYPE} (targets=${CG_TARGETS})"
        VERBATIM
    )

    add_custom_target(${CG_HWIP_TYPE}-codegen
        DEPENDS ${_stamp}
        COMMENT "deepspan-codegen: ${CG_HWIP_TYPE}"
    )
endfunction()
