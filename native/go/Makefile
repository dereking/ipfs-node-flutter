.PHONY: build-host verify-abi

build-host:
	mkdir -p dist
	go build -buildmode=c-shared -o dist/libipfs_node_core.dylib ./cmd/ipfs_node_core
	install_name_tool -id @rpath/libipfs_node_core.dylib dist/libipfs_node_core.dylib
	./scripts/package_header.sh dist/libipfs_node_core.h

verify-abi: build-host
	$(CC) -std=c11 -Wall -Werror -Idist test/abi_runtime_client.c -Ldist -lipfs_node_core -Wl,-rpath,@loader_path -o dist/abi_runtime_client
	./dist/abi_runtime_client
	test -f dist/libipfs_node_core.dylib
	test -f dist/libipfs_node_core.h
