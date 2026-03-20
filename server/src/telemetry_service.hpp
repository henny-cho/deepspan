// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <grpcpp/grpcpp.h>
#include "deepspan/v1/telemetry.grpc.pb.h"

namespace deepspan::server {

/// TelemetryService — stub implementation (returns empty snapshots).
class TelemetryServiceImpl final
    : public deepspan::v1::TelemetryService::Service {
public:
    grpc::Status GetTelemetry(
        grpc::ServerContext* ctx,
        const deepspan::v1::GetTelemetryRequest* req,
        deepspan::v1::GetTelemetryResponse* resp) override;
};

}  // namespace deepspan::server
