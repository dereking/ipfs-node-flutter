package go_core_test

import (
	"os"
	"strings"
	"testing"
)

func TestPublicHeaderDeclaresStableErrorCodesAndABI(t *testing.T) {
	header, err := os.ReadFile("include/ipfs_node_core.h")
	if err != nil {
		t.Fatal(err)
	}

	for _, declaration := range []string{
		"#define IPFS_NODE_OK 0",
		"#define IPFS_NODE_ERR_INVALID_HANDLE 1",
		"#define IPFS_NODE_ERR_INVALID_CONFIGURATION 2",
		"#define IPFS_NODE_ERR_INVALID_STATE 3",
		"uintptr_t ipfs_node_create(void);",
		"int ipfs_node_start(uintptr_t handle, char *request);",
		"int ipfs_node_stop(uintptr_t handle);",
		"char *ipfs_node_status(uintptr_t handle);",
		"char *ipfs_node_capabilities(uintptr_t handle);",
		"void ipfs_node_free(uintptr_t handle);",
		"void ipfs_node_free_string(char *value);",
	} {
		if !strings.Contains(string(header), declaration) {
			t.Errorf("header missing %q", declaration)
		}
	}
}
