# SPDX-License-Identifier: Apache-2.0
.PHONY: build test lint clean install-hooks

BINARY := deepspan-server
CMD     := ./cmd/server

build:
	go build -o $(BINARY) $(CMD)

test:
	go test ./...

lint:
	golangci-lint run ./...

clean:
	rm -f $(BINARY)

install-hooks:
	../scripts/install-hooks.sh
