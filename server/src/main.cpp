// SPDX-License-Identifier: Apache-2.0
// main.cpp — deepspan-server entry point
//
// Starts a single gRPC server on --addr (default :8080) that exposes:
//   HwipService       — routes to loaded HWIP plugins
//   ManagementService — owns OpenAMP transport (was l4/mgmt-daemon)
//   TelemetryService  — stub (always returns empty snapshot)
//
// Usage:
//   deepspan-server [--addr :8080] [--hwip-plugin /path/to/libhwip_accel.so ...]
//
// Multiple --hwip-plugin flags are allowed; each .so self-registers its
// factory via HwipRegistry at dlopen time.
#include <grpcpp/grpcpp.h>
#include <spdlog/spdlog.h>

#include <csignal>
#include <cstring>
#include <string>
#include <vector>

#include "deepspan/server/registry.hpp"
#include "hwip_service.hpp"
#include "mgmt_service.hpp"
#include "telemetry_service.hpp"

namespace {

volatile std::sig_atomic_t g_shutdown = 0;

void signal_handler(int sig) {
    spdlog::info("deepspan-server: received signal {}, shutting down", sig);
    g_shutdown = 1;
}

void print_usage(const char* argv0) {
    std::fprintf(stderr,
                 "Usage: %s [--addr ADDR] [--hwip-plugin PATH]...\n\n"
                 "  --addr ADDR          gRPC listen address (default: :8080)\n"
                 "  --hwip-plugin PATH   HWIP plugin shared library to load\n",
                 argv0);
}

}  // namespace

int main(int argc, char** argv) {
    std::string addr = ":8080";
    std::vector<std::string> plugin_paths;

    for (int i = 1; i < argc; ++i) {
        std::string_view arg{argv[i]};
        if (arg == "--addr" && i + 1 < argc) {
            addr = argv[++i];
        } else if (arg == "--hwip-plugin" && i + 1 < argc) {
            plugin_paths.emplace_back(argv[++i]);
        } else if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        } else {
            std::fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    spdlog::set_level(spdlog::level::info);
    spdlog::info("deepspan-server starting on {}", addr);

    // Load HWIP plugins — each .so self-registers via static Registrar.
    auto& registry = deepspan::server::HwipRegistry::instance();
    for (const auto& path : plugin_paths) {
        if (registry.load_plugin(path)) {
            spdlog::info("Loaded HWIP plugin: {}", path);
        } else {
            spdlog::error("Failed to load HWIP plugin: {}", path);
            return 1;
        }
    }

    auto registered = registry.registered_types();
    spdlog::info("Registered HWIP types: {}", [&] {
        std::string s;
        for (auto& t : registered) { if (!s.empty()) s += ", "; s += t; }
        return s.empty() ? "(none)" : s;
    }());

    // Build gRPC server with all three services.
    deepspan::server::HwipServiceImpl hwip_svc{registry};
    deepspan::server::MgmtServiceImpl mgmt_svc;
    deepspan::server::TelemetryServiceImpl telemetry_svc;

    grpc::ServerBuilder builder;
    builder.AddListeningPort(addr, grpc::InsecureServerCredentials());
    builder.RegisterService(&hwip_svc);
    builder.RegisterService(&mgmt_svc);
    builder.RegisterService(&telemetry_svc);

    auto server = builder.BuildAndStart();
    if (!server) {
        spdlog::error("Failed to start gRPC server on {}", addr);
        return 1;
    }
    spdlog::info("deepspan-server listening on {}", addr);

    // Block until SIGTERM/SIGINT.
    std::signal(SIGTERM, signal_handler);
    std::signal(SIGINT,  signal_handler);
    server->Wait();

    spdlog::info("deepspan-server stopped");
    return 0;
}
