// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <grpcpp/grpcpp.h>
#include "deepspan/v1/management.grpc.pb.h"

namespace deepspan::server {

/// ManagementService implementation.
///
/// Owns the OpenAMP transport directly (was previously a proxy to a separate
/// mgmt-daemon process). In simulation/stub mode the transport is a no-op.
class MgmtServiceImpl final
    : public deepspan::v1::ManagementService::Service {
public:
    MgmtServiceImpl();
    ~MgmtServiceImpl() override;

    grpc::Status GetFirmwareInfo(
        grpc::ServerContext* ctx,
        const deepspan::v1::GetFirmwareInfoRequest* req,
        deepspan::v1::GetFirmwareInfoResponse* resp) override;

    grpc::Status ResetDevice(
        grpc::ServerContext* ctx,
        const deepspan::v1::ResetDeviceRequest* req,
        deepspan::v1::ResetDeviceResponse* resp) override;

    grpc::Status PushConfig(
        grpc::ServerContext* ctx,
        const deepspan::v1::PushConfigRequest* req,
        deepspan::v1::PushConfigResponse* resp) override;

    grpc::Status GetConsolePath(
        grpc::ServerContext* ctx,
        const deepspan::v1::GetConsolePathRequest* req,
        deepspan::v1::GetConsolePathResponse* resp) override;
};

}  // namespace deepspan::server
