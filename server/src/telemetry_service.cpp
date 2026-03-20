// SPDX-License-Identifier: Apache-2.0
#include "telemetry_service.hpp"

#include <spdlog/spdlog.h>

namespace deepspan::server {

grpc::Status TelemetryServiceImpl::GetTelemetry(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::GetTelemetryRequest* req,
    deepspan::v1::GetTelemetryResponse* resp) {
    spdlog::debug("GetTelemetry: device_id={}", req->device_id());
    // Stub: return zero-filled snapshot.
    // Stub: return a zero-filled snapshot with just the device_id populated.
    auto* snap = resp->mutable_snapshot();
    snap->set_device_id(req->device_id());
    return grpc::Status::OK;
}

}  // namespace deepspan::server
