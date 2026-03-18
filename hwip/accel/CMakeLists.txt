# SPDX-License-Identifier: Apache-2.0
# hwip/accel/CMakeLists.txt — Acceleration HWIP plugin build integration
#
# Included by the root CMakeLists.txt when DEEPSPAN_HWIP_TYPE=accel.
# Adds accel-specific:
#   - hw-model register map header path
#   - firmware driver (when DEEPSPAN_BUILD_FIRMWARE is ON)
#   - kernel UAPI header (deepspan_accel.h)

cmake_minimum_required(VERSION 3.25)

# ── hw-model integration ──────────────────────────────────────────────────────
if(TARGET deepspan_hw_model)
    target_include_directories(deepspan_hw_model PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/hw-model/include
    )
endif()

# ── Firmware driver (Zephyr module) ──────────────────────────────────────────
# When building firmware via west, add this directory as a Zephyr module.
# west build command: ZEPHYR_EXTRA_MODULES=$(pwd)/hwip/accel/firmware
# See hwip/README.md for full instructions.

# ── Kernel UAPI header installation ──────────────────────────────────────────
# Copy deepspan_accel.h alongside deepspan.h so userlib can use:
#   #include <linux/deepspan_accel.h>
install(FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/kernel/deepspan_accel.h
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/linux
)

message(STATUS "hwip/accel plugin configured (DEEPSPAN_HWIP_TYPE=accel)")
