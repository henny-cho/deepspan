// SPDX-License-Identifier: Apache-2.0
// mgmt_service.cpp — ManagementService with direct OpenAMP transport
//
// This file consolidates what was previously two processes:
//   l4/server    (ConnectRPC proxy → mgmt-daemon)
//   l4/mgmt-daemon (OpenAMP RPMsg handler)
//
// In C++20 the ManagementService owns the transport directly, eliminating
// the inter-process proxy layer.
#include "mgmt_service.hpp"

#include <spdlog/spdlog.h>

namespace deepspan::server {

MgmtServiceImpl::MgmtServiceImpl() {
    // TODO: initialise OpenAMP transport here (or a stub transport for sim).
    spdlog::info("MgmtServiceImpl: initialised (stub transport)");
}

MgmtServiceImpl::~MgmtServiceImpl() {
    spdlog::info("MgmtServiceImpl: shutting down transport");
}

grpc::Status MgmtServiceImpl::GetFirmwareInfo(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::GetFirmwareInfoRequest* req,
    deepspan::v1::GetFirmwareInfoResponse* resp) {
    spdlog::debug("GetFirmwareInfo: device_id={}", req->device_id());
    // TODO: query firmware via OpenAMP RPMsg.
    resp->set_fw_version("0.0.0-stub");
    resp->set_build_date("1970-01-01");
    resp->set_protocol_version(1);
    return grpc::Status::OK;
}

grpc::Status MgmtServiceImpl::ResetDevice(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::ResetDeviceRequest* req,
    deepspan::v1::ResetDeviceResponse* resp) {
    spdlog::info("ResetDevice: device_id={} force={}", req->device_id(), req->force());
    // TODO: send reset command over OpenAMP.
    resp->set_success(true);
    return grpc::Status::OK;
}

grpc::Status MgmtServiceImpl::PushConfig(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::PushConfigRequest* req,
    deepspan::v1::PushConfigResponse* resp) {
    spdlog::info("PushConfig: device_id={} keys={}", req->device_id(),
                 req->config_size());
    // TODO: forward config over OpenAMP RPMsg.
    (void)resp;
    return grpc::Status::OK;
}

grpc::Status MgmtServiceImpl::GetConsolePath(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::GetConsolePathRequest* req,
    deepspan::v1::GetConsolePathResponse* resp) {
    spdlog::debug("GetConsolePath: device_id={}", req->device_id());
    // TODO: return the PTY path allocated by OpenAMP transport.
    resp->set_pty_path("/dev/null");
    return grpc::Status::OK;
}

}  // namespace deepspan::server
