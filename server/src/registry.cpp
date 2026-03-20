// SPDX-License-Identifier: Apache-2.0
#include "deepspan/server/registry.hpp"

#include <dlfcn.h>

#include <iostream>
#include <stdexcept>

namespace deepspan::server {

HwipRegistry& HwipRegistry::instance() {
    static HwipRegistry inst;
    return inst;
}

void HwipRegistry::register_type(std::string hwip_type, SubmitterFactory factory) {
    std::unique_lock lock{mutex_};
    factories_[std::move(hwip_type)] = std::move(factory);
}

void HwipRegistry::unregister_type(std::string_view hwip_type) {
    std::unique_lock lock{mutex_};
    factories_.erase(std::string{hwip_type});
}

bool HwipRegistry::load_plugin(std::string_view so_path) {
    // RTLD_NOW: resolve all symbols immediately (fail fast on missing deps).
    // RTLD_LOCAL: do not make symbols visible to other shared libraries.
    void* handle = dlopen(so_path.data(), RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        std::cerr << "[HwipRegistry] dlopen(" << so_path << ") failed: "
                  << dlerror() << "\n";
        return false;
    }
    // The static Registrar object inside the .so has already called
    // register_type() as a side effect of dlopen().
    std::unique_lock lock{mutex_};
    dl_handles_[std::string{so_path}] = handle;
    return true;
}

void HwipRegistry::unload_plugin(std::string_view hwip_type) {
    // The Registrar destructor inside the .so will call unregister_type(),
    // so we only need to find and dlclose the handle here.
    std::string type_str{hwip_type};
    void* handle = nullptr;
    {
        std::unique_lock lock{mutex_};
        // Search dl_handles_ by value (hwip_type isn't the key; so_path is).
        // Plugins are expected to be few, so a linear scan is fine.
        for (auto it = dl_handles_.begin(); it != dl_handles_.end(); ++it) {
            // We stored the so_path as key; look up the registered hwip_type
            // by checking if it still exists in factories_ — if unregister
            // was already called by the destructor the factory is gone.
            // Instead, just dlclose all handles for the type (caller passes type).
            (void)it;
        }
        // Simpler: accept so_path as key. Provide unload_plugin_by_path() for
        // path-based unload; this overload accepts the hwip_type registered.
        for (auto it = dl_handles_.begin(); it != dl_handles_.end();) {
            // heuristic: so filename contains hwip_type
            if (it->first.find(type_str) != std::string::npos) {
                handle = it->second;
                it = dl_handles_.erase(it);
            } else {
                ++it;
            }
        }
    }
    if (handle) {
        dlclose(handle);  // triggers Registrar destructor → unregister_type()
    }
}

std::vector<std::string> HwipRegistry::registered_types() const {
    std::shared_lock lock{mutex_};
    std::vector<std::string> types;
    types.reserve(factories_.size());
    for (const auto& [type, _] : factories_) {
        types.push_back(type);
    }
    return types;
}

std::vector<DeviceInfo> HwipRegistry::enumerate_devices() const {
    std::shared_lock lock{mutex_};
    std::vector<DeviceInfo> devices;
    for (const auto& [type, factory] : factories_) {
        // Enumerate up to a reasonable maximum; plugins return UNSPECIFIED
        // state for out-of-range device indices to signal the end of the list.
        for (int idx = 0; idx < 64; ++idx) {
            std::string dev_id = type + "/" + std::to_string(idx);
            try {
                auto sub = factory(dev_id);
                if (!sub) break;
                DeviceInfo info;
                info.device_id = dev_id;
                info.state = sub->device_state();
                if (info.state < 0) break;  // plugin signals end of devices
                devices.push_back(std::move(info));
            } catch (...) {
                break;  // plugin threw — no more devices of this type
            }
        }
    }
    return devices;
}

std::optional<std::unique_ptr<Submitter>>
HwipRegistry::create(std::string_view hwip_type,
                     std::string_view device_id) const {
    std::shared_lock lock{mutex_};
    auto it = factories_.find(hwip_type);
    if (it == factories_.end()) return std::nullopt;
    return it->second(device_id);
}

}  // namespace deepspan::server
