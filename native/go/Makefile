.PHONY: build-host

build-host:
	mkdir -p dist
	go build -buildmode=c-shared -o dist/libipfs_node_core.dylib ./cmd/ipfs_node_core
