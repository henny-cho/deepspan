# SPDX-License-Identifier: Apache-2.0
# FindGRPC.cmake — find gRPC C++ installation
#
# This module is used when gRPC is installed via a system package manager
# or vcpkg and does NOT ship a gRPCConfig.cmake. When gRPC ships its own
# CMake config (e.g. via vcpkg or a modern install), find_package(gRPC CONFIG)
# is preferred and this module is not needed.
#
# Targets created:
#   gRPC::grpc++            — C++ gRPC library
#   gRPC::grpc_cpp_plugin   — protoc-gen-grpc code generator binary
#
# Variables:
#   gRPC_FOUND              — TRUE if gRPC was found
#   gRPC_VERSION            — version string (if detectable)
#
# Usage (in CMakeLists.txt):
#   find_package(gRPC REQUIRED)   # falls back to this module if no gRPCConfig

include(FindPackageHandleStandardArgs)

# Try pkg-config first (most Linux distros).
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(PC_GRPCPP QUIET grpc++)
    pkg_check_modules(PC_GRPC   QUIET grpc)
endif()

find_library(gRPC_LIBRARY
    NAMES grpc++
    HINTS ${PC_GRPCPP_LIBRARY_DIRS}
    DOC "gRPC C++ library"
)

find_library(gRPC_CORE_LIBRARY
    NAMES grpc
    HINTS ${PC_GRPC_LIBRARY_DIRS}
    DOC "gRPC core library"
)

find_path(gRPC_INCLUDE_DIR
    NAMES grpcpp/grpcpp.h
    HINTS ${PC_GRPCPP_INCLUDE_DIRS}
    DOC "gRPC C++ include directory"
)

find_program(gRPC_CPP_PLUGIN
    NAMES grpc_cpp_plugin
    DOC "gRPC C++ protoc plugin binary"
)

find_package_handle_standard_args(gRPC
    REQUIRED_VARS gRPC_LIBRARY gRPC_INCLUDE_DIR gRPC_CPP_PLUGIN
    VERSION_VAR   PC_GRPCPP_VERSION
)

if(gRPC_FOUND AND NOT TARGET gRPC::grpc++)
    add_library(gRPC::grpc++ UNKNOWN IMPORTED)
    set_target_properties(gRPC::grpc++ PROPERTIES
        IMPORTED_LOCATION "${gRPC_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${gRPC_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "${gRPC_CORE_LIBRARY}"
    )

    add_executable(gRPC::grpc_cpp_plugin IMPORTED)
    set_target_properties(gRPC::grpc_cpp_plugin PROPERTIES
        IMPORTED_LOCATION "${gRPC_CPP_PLUGIN}"
    )
endif()
