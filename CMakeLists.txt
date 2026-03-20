cmake_minimum_required(VERSION 3.27)
project(Deepspan VERSION 0.2.0 LANGUAGES C CXX)

include(GNUInstallDirs)

# ── Options ───────────────────────────────────────────────────────────
option(DEEPSPAN_BUILD_HW_MODEL     "Build hw-model simulator (sim/)"    ON)
option(DEEPSPAN_BUILD_USERLIB      "Build userlib (runtime/userlib/)"   ON)
option(DEEPSPAN_BUILD_APPFRAMEWORK "Build appframework (runtime/)"      ON)
option(DEEPSPAN_BUILD_SERVER       "Build C++20 gRPC server (server/)"  ON)
option(DEEPSPAN_BUILD_FIRMWARE     "Build Zephyr firmware (West)"       OFF)
option(DEEPSPAN_BUILD_KERNEL       "Build Linux kernel module"          OFF)
option(DEEPSPAN_BUILD_TESTS        "Build tests"                        ON)
option(DEEPSPAN_BUILD_HWIP         "Build HWIP plugin(s)"              OFF)
# Comma-separated list of HWIP types to build (e.g. "accel,codec").
# Set HWIP_TYPES to build multiple plugins in one cmake run.
set(HWIP_TYPES "accel" CACHE STRING "Comma-separated HWIP type(s) to build")
# Backward-compat single-type alias (deprecated: prefer HWIP_TYPES)
set(HWIP_TYPE "accel" CACHE STRING "HWIP type to build (use HWIP_TYPES for multi)")

if(DEEPSPAN_BUILD_TESTS)
    enable_testing()
endif()
option(DEEPSPAN_USE_SYSTEM_DEPS   "Use system/vcpkg packages (OFF=submodule)" ON)

# ── Dependencies ──────────────────────────────────────────────────────
if(NOT DEEPSPAN_USE_SYSTEM_DEPS)
    # git submodule approach: build sources from third_party/
    if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/googletest/CMakeLists.txt")
        add_subdirectory(third_party/googletest EXCLUDE_FROM_ALL)
    endif()
    if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/spdlog/CMakeLists.txt")
        add_subdirectory(third_party/spdlog EXCLUDE_FROM_ALL)
    endif()
else()
    find_package(GTest QUIET)
    find_package(spdlog QUIET)
endif()

# ETL (Embedded Template Library) — firmware/Zephyr only.
if(DEEPSPAN_BUILD_FIRMWARE)
    if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/etl/CMakeLists.txt")
        add_subdirectory(third_party/etl EXCLUDE_FROM_ALL)
    endif()
endif()

# gRPC C++ — required by server/ and HWIP plugins.
if(DEEPSPAN_BUILD_SERVER OR DEEPSPAN_BUILD_HWIP)
    find_package(gRPC CONFIG REQUIRED)
    find_package(Protobuf CONFIG REQUIRED)
endif()

# ── Component builds ──────────────────────────────────────────────────
if(DEEPSPAN_BUILD_HW_MODEL)
    add_subdirectory(sim/hw-model)
endif()

if(DEEPSPAN_BUILD_USERLIB)
    add_subdirectory(runtime/userlib)
endif()

if(DEEPSPAN_BUILD_APPFRAMEWORK)
    add_subdirectory(runtime/appframework)
endif()

if(DEEPSPAN_BUILD_SERVER)
    add_subdirectory(server)
endif()

if(DEEPSPAN_BUILD_KERNEL)
    include(ExternalProject)
    ExternalProject_Add(deepspan-kernel
        SOURCE_DIR  ${CMAKE_SOURCE_DIR}/kernel
        BINARY_DIR  ${CMAKE_BINARY_DIR}/kernel
        CONFIGURE_COMMAND ""
        BUILD_COMMAND
            $(MAKE) -C /lib/modules/$ENV{KVER}/build
            M=${CMAKE_SOURCE_DIR}/kernel/drivers/deepspan
            modules
            CONFIG_DEEPSPAN_TRANSPORT_SIM=y
        INSTALL_COMMAND ""
        BUILD_ALWAYS TRUE
    )
endif()

if(DEEPSPAN_BUILD_HWIP)
    include(cmake/hwip-plugin.cmake)
    # Support comma-separated HWIP_TYPES list or legacy single HWIP_TYPE.
    if(HWIP_TYPES AND NOT HWIP_TYPES STREQUAL "accel")
        string(REPLACE "," ";" _hwip_list "${HWIP_TYPES}")
    else()
        set(_hwip_list "${HWIP_TYPE}")
    endif()
    foreach(_hwip IN LISTS _hwip_list)
        if(EXISTS "${CMAKE_SOURCE_DIR}/hwip/${_hwip}/CMakeLists.txt")
            add_subdirectory("hwip/${_hwip}")
        else()
            message(WARNING "HWIP type '${_hwip}' not found at hwip/${_hwip}/")
        endif()
    endforeach()
endif()

# ── Platform install export ───────────────────────────────────────────
# Enables external repos (e.g. deepspan-accel) to consume the platform
# libraries via find_package(DeepspanPlatform REQUIRED).
if(DEEPSPAN_BUILD_APPFRAMEWORK AND DEEPSPAN_BUILD_USERLIB)
    include(CMakePackageConfigHelpers)
    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/DeepspanPlatformConfigVersion.cmake"
        VERSION ${PROJECT_VERSION}
        COMPATIBILITY SameMajorVersion
    )
    install(EXPORT DeepspanPlatformTargets
        NAMESPACE Deepspan::
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/DeepspanPlatform
    )
    install(FILES
        cmake/DeepspanPlatformConfig.cmake
        "${CMAKE_CURRENT_BINARY_DIR}/DeepspanPlatformConfigVersion.cmake"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/DeepspanPlatform
    )
endif()
