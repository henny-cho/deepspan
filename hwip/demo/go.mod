module github.com/myorg/deepspan-hwip/demo

go 1.26.1

require (
	connectrpc.com/connect v1.17.0
	github.com/myorg/deepspan-hwip/accel/gen/go v0.0.0-00010101000000-000000000000
	github.com/myorg/deepspan-hwip/accel/l4-plugin v0.0.0-00010101000000-000000000000
	github.com/myorg/deepspan/l4/server v0.0.0-00010101000000-000000000000
	github.com/myorg/deepspan/l5/gen v0.0.0-00010101000000-000000000000
	golang.org/x/net v0.38.0
	google.golang.org/protobuf v1.36.5
)

replace (
	github.com/myorg/deepspan-hwip/accel/gen/go => ../accel/gen/go
	github.com/myorg/deepspan-hwip/accel/l4-plugin => ../accel/l4-plugin
	github.com/myorg/deepspan/l4/server => ../../l4/server
	github.com/myorg/deepspan/l5/gen => ../../l5/gen/go
)
