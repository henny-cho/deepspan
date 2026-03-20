# SPDX-License-Identifier: Apache-2.0
# server/CMakeLists.txt — C++20 gRPC server (HwipService + ManagementService + TelemetryService)
#
# Requires: gRPC C++ (system package or vcpkg), protobuf, spdlog
# Proto stubs (*.pb.cc / *.grpc.pb.cc) are generated at configure/build time
# via explicit add_custom_command — they are NOT committed.

cmake_minimum_required(VERSION 3.27)

find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf REQUIRED)

# ── Proto stub generation ─────────────────────────────────────────────────────
set(PROTO_SRC_DIR "${CMAKE_SOURCE_DIR}/api/proto")
file(GLOB_RECURSE PROTO_FILES "${PROTO_SRC_DIR}/*.proto")

get_target_property(GRPC_CPP_PLUGIN_EXE gRPC::grpc_cpp_plugin LOCATION)

set(PROTO_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/proto_gen")
file(MAKE_DIRECTORY "${PROTO_OUT_DIR}")

set(PROTO_SRCS "")
set(GRPC_SRCS  "")

foreach(_proto_file ${PROTO_FILES})
    # Relative path from the import root (api/proto/) → deepspan/v1/device.proto
    file(RELATIVE_PATH _rel_path "${PROTO_SRC_DIR}" "${_proto_file}")
    get_filename_component(_rel_dir  "${_rel_path}" DIRECTORY)
    get_filename_component(_basename "${_rel_path}" NAME_WLE)

    set(_pb_cc   "${PROTO_OUT_DIR}/${_rel_dir}/${_basename}.pb.cc")
    set(_pb_h    "${PROTO_OUT_DIR}/${_rel_dir}/${_basename}.pb.h")
    set(_grpc_cc "${PROTO_OUT_DIR}/${_rel_dir}/${_basename}.grpc.pb.cc")
    set(_grpc_h  "${PROTO_OUT_DIR}/${_rel_dir}/${_basename}.grpc.pb.h")

    add_custom_command(
        OUTPUT "${_pb_cc}" "${_pb_h}" "${_grpc_cc}" "${_grpc_h}"
        COMMAND "${Protobuf_PROTOC_EXECUTABLE}"
            "--cpp_out=${PROTO_OUT_DIR}"
            "--grpc_out=${PROTO_OUT_DIR}"
            "--plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXE}"
            "-I${PROTO_SRC_DIR}"
            "${_proto_file}"
        DEPENDS "${_proto_file}"
        COMMENT "Compiling proto: ${_rel_path}"
    )

    list(APPEND PROTO_SRCS "${_pb_cc}")
    list(APPEND GRPC_SRCS  "${_grpc_cc}")
endforeach()

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

# Export all symbols from the server executable so dlopen'd HWIP plugins
# (e.g. libhwip_accel.so) can resolve HwipRegistry and other server-side symbols.
target_link_options(deepspan-server PRIVATE -Wl,-export-dynamic)

# ── Install ───────────────────────────────────────────────────────────────────
install(TARGETS deepspan-server
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)
