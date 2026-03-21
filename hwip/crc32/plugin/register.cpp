// SPDX-License-Identifier: Apache-2.0
// register.cpp — static Registrar for hwip_crc32.so
//
// When dlopen() loads this shared library the static `reg` object is
// constructed, calling HwipRegistry::register_type("crc32", ...).
// When dlclose() unloads the library the destructor is called, which
// calls HwipRegistry::unregister_type("crc32").
#include "crc32_plugin.hpp"
#include "deepspan/server/registry.hpp"

namespace {

struct Crc32Registrar {
    Crc32Registrar() {
        deepspan::server::HwipRegistry::instance().register_type(
            "crc32",
            [](std::string_view device_id) {
                return std::make_unique<deepspan::hwip::crc32::Crc32Plugin>(
                    device_id);
            });
    }

    ~Crc32Registrar() {
        deepspan::server::HwipRegistry::instance().unregister_type("crc32");
    }
};

// Static object — constructed at .so load time, destructed at .so unload time.
static Crc32Registrar reg;  // NOLINT(cert-err58-cpp)

}  // namespace
