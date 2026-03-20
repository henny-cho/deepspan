module github.com/myorg/deepspan-hwip/accel/l4-plugin

go 1.26.1

require (
	// Platform Tier-1 interfaces (resolved via go.work in monorepo).
	github.com/myorg/deepspan/l4/server v0.0.0-00010101000000-000000000000
	github.com/myorg/deepspan/l5/gen v0.0.0-00010101000000-000000000000
	// Generated ConnectRPC stubs for this HWIP.
	github.com/myorg/deepspan-hwip/accel/gen/go v0.0.0-00010101000000-000000000000
	// External deps.
	connectrpc.com/connect v1.17.0
	golang.org/x/sys v0.34.0
	google.golang.org/protobuf v1.36.5
)

replace (
	github.com/myorg/deepspan/l4/server => ../../../l4/server
	github.com/myorg/deepspan/l5/gen => ../../../l5/gen/go
	github.com/myorg/deepspan-hwip/accel/gen/go => ../gen/go
)
