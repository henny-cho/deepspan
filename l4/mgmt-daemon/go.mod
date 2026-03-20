module github.com/myorg/deepspan/l4/mgmt-daemon

go 1.26.1

require (
	connectrpc.com/connect v1.17.0
	github.com/myorg/deepspan/l5/gen v0.0.0-00010101000000-000000000000
	golang.org/x/net v0.38.0
)

replace github.com/myorg/deepspan/l5/gen => ../../l5/gen/go

require (
	golang.org/x/text v0.23.0 // indirect
	google.golang.org/protobuf v1.36.5 // indirect
)
