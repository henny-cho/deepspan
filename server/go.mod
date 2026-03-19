module github.com/myorg/deepspan/server

go 1.26.1

require (
	connectrpc.com/connect v1.16.2
	github.com/myorg/deepspan/gen/go v0.0.0-00010101000000-000000000000
	golang.org/x/net v0.27.0
	google.golang.org/protobuf v1.34.2
)

replace github.com/myorg/deepspan/gen/go => ../gen/go

require golang.org/x/text v0.16.0 // indirect
