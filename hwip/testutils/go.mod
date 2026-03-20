module github.com/myorg/deepspan/hwip/shared/testutils

go 1.26.1

require github.com/myorg/deepspan/l4/server v0.0.0-00010101000000-000000000000

require (
	connectrpc.com/connect v1.17.0 // indirect
	github.com/google/go-cmp v0.6.0 // indirect
	google.golang.org/protobuf v1.36.5 // indirect
)

replace github.com/myorg/deepspan/l4/server => ../../../l4/server
