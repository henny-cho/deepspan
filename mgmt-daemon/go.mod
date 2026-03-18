module github.com/myorg/deepspan/mgmt-daemon

go 1.26.1

require (
	connectrpc.com/connect v1.16.2
	github.com/myorg/deepspan/gen/go v0.0.0-00010101000000-000000000000
	golang.org/x/net v0.27.0
)

replace github.com/myorg/deepspan/gen/go => ../gen/go

require (
	github.com/google/go-cmp v0.5.9 // indirect
	golang.org/x/text v0.16.0 // indirect
	google.golang.org/protobuf v1.34.2 // indirect
)
