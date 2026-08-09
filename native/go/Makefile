.PHONY: build-host verify-abi

build-host:
	mkdir -p dist
	go build -buildmode=c-shared -o dist/libipfs_node_core.dylib ./cmd/ipfs_node_core

verify-abi: build-host
	$(CC) -std=c11 -Iinclude -fsyntax-only test/abi_header_smoke.c
	test -f dist/libipfs_node_core.dylib
	test -f dist/libipfs_node_core.h
