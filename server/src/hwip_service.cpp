// SPDX-License-Identifier: Apache-2.0
#include "hwip_service.hpp"

#include <spdlog/spdlog.h>

#include <stdexcept>

namespace deepspan::server {

bool HwipServiceImpl::parse_device_id(std::string_view device_id,
                                       std::string& hwip_type,
                                       std::string& index) {
    auto slash = device_id.find('/');
    if (slash == std::string_view::npos || slash == 0 ||
        slash == device_id.size() - 1) {
        return false;
    }
    hwip_type = std::string{device_id.substr(0, slash)};
    index = std::string{device_id.substr(slash + 1)};
    return true;
}

grpc::Status HwipServiceImpl::ListDevices(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::ListDevicesRequest* /*req*/,
    deepspan::v1::ListDevicesResponse* resp) {
    for (auto& info : registry_.enumerate_devices()) {
        auto* dev = resp->add_devices();
        dev->set_device_id(info.device_id);
        dev->set_state(
            static_cast<deepspan::v1::DeviceState>(info.state));
    }
    return grpc::Status::OK;
}

grpc::Status HwipServiceImpl::GetDeviceStatus(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::GetDeviceStatusRequest* req,
    deepspan::v1::GetDeviceStatusResponse* resp) {
    std::string hwip_type, idx;
    if (!parse_device_id(req->device_id(), hwip_type, idx)) {
        return grpc::Status{grpc::StatusCode::INVALID_ARGUMENT,
                            "invalid device_id format (expected <type>/<index>)"};
    }
    auto sub_opt = registry_.create(hwip_type, req->device_id());
    if (!sub_opt) {
        return grpc::Status{grpc::StatusCode::NOT_FOUND,
                            "HWIP type not registered: " + hwip_type};
    }
    resp->set_device_id(req->device_id());
    resp->set_state(
        static_cast<deepspan::v1::DeviceState>((*sub_opt)->device_state()));
    return grpc::Status::OK;
}

grpc::Status HwipServiceImpl::SubmitRequest(
    grpc::ServerContext* /*ctx*/,
    const deepspan::v1::SubmitRequestRequest* req,
    deepspan::v1::SubmitRequestResponse* resp) {
    std::string hwip_type, idx;
    if (!parse_device_id(req->device_id(), hwip_type, idx)) {
        return grpc::Status{grpc::StatusCode::INVALID_ARGUMENT,
                            "invalid device_id format (expected <type>/<index>)"};
    }
    auto sub_opt = registry_.create(hwip_type, req->device_id());
    if (!sub_opt) {
        return grpc::Status{grpc::StatusCode::NOT_FOUND,
                            "HWIP type not registered: " + hwip_type};
    }
    auto& sub = *sub_opt;
    try {
        const auto& raw = req->data();
        std::vector<uint8_t> data{raw.begin(), raw.end()};
        auto result = sub->submit(req->opcode(), std::move(data));
        resp->set_request_id(result.request_id);
        resp->set_response_data(
            std::string{result.response_data.begin(), result.response_data.end()});
    } catch (const std::exception& e) {
        spdlog::error("SubmitRequest failed for {}: {}", req->device_id(), e.what());
        return grpc::Status{grpc::StatusCode::INTERNAL, e.what()};
    }
    return grpc::Status::OK;
}

}  // namespace deepspan::server
