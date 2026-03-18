# SPDX-License-Identifier: Apache-2.0
.PHONY: build test lint clean

BINARY := mgmt-daemon
CMD     := ./cmd/mgmt-daemon

build:
	go build -o $(BINARY) $(CMD)

test:
	go test ./...

lint:
	golangci-lint run ./...

clean:
	rm -f $(BINARY)
