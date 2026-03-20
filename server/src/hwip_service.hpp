// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <grpcpp/grpcpp.h>
#include "deepspan/server/registry.hpp"
// Generated proto headers (produced by CMake protobuf_generate at build time)
#include "deepspan/v1/device.grpc.pb.h"

namespace deepspan::server {

class HwipServiceImpl final
    : public deepspan::v1::HwipService::Service {
public:
    explicit HwipServiceImpl(HwipRegistry& registry) : registry_{registry} {}

    grpc::Status ListDevices(
        grpc::ServerContext* ctx,
        const deepspan::v1::ListDevicesRequest* req,
        deepspan::v1::ListDevicesResponse* resp) override;

    grpc::Status GetDeviceStatus(
        grpc::ServerContext* ctx,
        const deepspan::v1::GetDeviceStatusRequest* req,
        deepspan::v1::GetDeviceStatusResponse* resp) override;

    grpc::Status SubmitRequest(
        grpc::ServerContext* ctx,
        const deepspan::v1::SubmitRequestRequest* req,
        deepspan::v1::SubmitRequestResponse* resp) override;

private:
    HwipRegistry& registry_;

    /// Parse "accel/0" → {"accel", "0"}; returns false on bad format.
    static bool parse_device_id(std::string_view device_id,
                                 std::string& hwip_type,
                                 std::string& index);
};

}  // namespace deepspan::server
