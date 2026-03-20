# SPDX-License-Identifier: Apache-2.0
# server/CMakeLists.txt — C++20 gRPC server (HwipService + ManagementService + TelemetryService)
#
# Requires: gRPC C++ (system package or vcpkg), protobuf, spdlog
# The proto stubs (*.pb.cc / *.grpc.pb.cc) are generated at configure time by
# protobuf_generate() and grpc_generate_cpp() — they are NOT committed.

cmake_minimum_required(VERSION 3.27)

find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf CONFIG REQUIRED)

# ── Proto stub generation ─────────────────────────────────────────────────────
# Platform protos (api/proto/) generate C++ stubs into the build directory.
set(PROTO_SRC_DIR "${CMAKE_SOURCE_DIR}/api/proto")
file(GLOB_RECURSE PROTO_FILES "${PROTO_SRC_DIR}/*.proto")

# protobuf + gRPC code generation
set(PROTO_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/proto_gen")
file(MAKE_DIRECTORY "${PROTO_OUT_DIR}")

# Generate .pb.cc / .pb.h
protobuf_generate(
    LANGUAGE cpp
    OUT_VAR PROTO_SRCS
    PROTOS ${PROTO_FILES}
    IMPORT_DIRS "${PROTO_SRC_DIR}"
    PROTOC_OUT_DIR "${PROTO_OUT_DIR}"
)

# Generate .grpc.pb.cc / .grpc.pb.h
get_target_property(GRPC_CPP_PLUGIN_EXE gRPC::grpc_cpp_plugin LOCATION)
protobuf_generate(
    LANGUAGE grpc
    OUT_VAR GRPC_SRCS
    GENERATE_EXTENSIONS .grpc.pb.h .grpc.pb.cc
    PLUGIN "protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}"
    PROTOS ${PROTO_FILES}
    IMPORT_DIRS "${PROTO_SRC_DIR}"
    PROTOC_OUT_DIR "${PROTO_OUT_DIR}"
)

# ── deepspan-server executable ────────────────────────────────────────────────
add_executable(deepspan-server
    src/main.cpp
    src/hwip_service.cpp
    src/mgmt_service.cpp
    src/telemetry_service.cpp
    src/registry.cpp
    ${PROTO_SRCS}
    ${GRPC_SRCS}
)

target_compile_features(deepspan-server PRIVATE cxx_std_20)

target_include_directories(deepspan-server
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${PROTO_OUT_DIR}"
)

target_link_libraries(deepspan-server
    PRIVATE
        deepspan-appframework
        deepspan-userlib
        gRPC::grpc++
        protobuf::libprotobuf
        spdlog::spdlog
        dl          # for dlopen/dlclose in registry.cpp
)

# ── Install ───────────────────────────────────────────────────────────────────
install(TARGETS deepspan-server
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)
