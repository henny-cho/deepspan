// SPDX-License-Identifier: Apache-2.0
// register.cpp — static Registrar for hwip_accel.so
//
// When dlopen() loads this shared library the static `reg` object is
// constructed, calling HwipRegistry::register_type("accel", ...).
// When dlclose() unloads the library the destructor is called, which
// calls HwipRegistry::unregister_type("accel").
#include "accel_plugin.hpp"
#include "deepspan/server/registry.hpp"

namespace {

struct AccelRegistrar {
    AccelRegistrar() {
        deepspan::server::HwipRegistry::instance().register_type(
            "accel",
            [](std::string_view device_id) {
                return std::make_unique<deepspan::hwip::accel::AccelPlugin>(device_id);
            });
    }

    ~AccelRegistrar() {
        deepspan::server::HwipRegistry::instance().unregister_type("accel");
    }
};

// Static object — constructed at .so load time, destructed at .so unload time.
static AccelRegistrar reg;  // NOLINT(cert-err58-cpp)

}  // namespace
