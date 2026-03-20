// SPDX-License-Identifier: Apache-2.0
// registry.hpp — Dynamic HWIP plugin registry (C++20)
//
// Plugins register factories via register_type(), either at static init time
// (when the .so is dlopen'd) or explicitly. The server calls create() to
// instantiate Submitters and enumerate_devices() to aggregate ListDevices().
#pragma once

#include "submitter.hpp"

#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <vector>

namespace deepspan::server {

/// Factory function type: given a device_id, produce a Submitter.
using SubmitterFactory =
    std::function<std::unique_ptr<Submitter>(std::string_view device_id)>;

/// Singleton registry of HWIP plugin factories.
///
/// Thread-safe: register/unregister use a writer lock; create/enumerate use a
/// reader lock, so concurrent reads do not block each other.
class HwipRegistry {
public:
    static HwipRegistry& instance();

    // ── Registration ──────────────────────────────────────────────────────────

    /// Register a factory for the given hwip_type (e.g. "accel", "codec").
    /// Called automatically from static Registrar objects inside plugin .so
    /// files when dlopen() loads them.
    void register_type(std::string hwip_type, SubmitterFactory factory);

    /// Unregister a factory. Called from the plugin's Registrar destructor
    /// when the .so is unloaded via dlclose().
    void unregister_type(std::string_view hwip_type);

    // ── Dynamic plugin loading ────────────────────────────────────────────────

    /// dlopen a plugin .so by path. The static Registrar inside the .so calls
    /// register_type() automatically. The handle is stored for later unload.
    /// Returns false if dlopen fails (error logged to stderr).
    bool load_plugin(std::string_view so_path);

    /// dlclose a plugin loaded by load_plugin() and unregister its type.
    void unload_plugin(std::string_view hwip_type);

    // ── Device management ─────────────────────────────────────────────────────

    /// Return all registered hwip_type strings (e.g. {"accel", "codec"}).
    std::vector<std::string> registered_types() const;

    /// Aggregate DeviceInfo from all registered plugins.
    /// Each plugin's factory is called for device ids "<type>/0", "<type>/1", ...
    /// up to the number of physical devices it reports.
    std::vector<DeviceInfo> enumerate_devices() const;

    /// Create a Submitter for the given hwip_type + device_id.
    /// Returns std::nullopt if the type is not registered.
    std::optional<std::unique_ptr<Submitter>>
    create(std::string_view hwip_type, std::string_view device_id) const;

private:
    HwipRegistry() = default;

    mutable std::shared_mutex mutex_;
    std::map<std::string, SubmitterFactory, std::less<>> factories_;
    std::map<std::string, void*> dl_handles_;  ///< so_path → dlopen handle
};

}  // namespace deepspan::server
