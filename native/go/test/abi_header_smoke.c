#include "ipfs_node_core.h"

void ipfs_node_abi_header_smoke(void) {
  char request[] = "{\"network\":\"public\"}";
  uintptr_t handle = ipfs_node_create();
  int result = ipfs_node_start(handle, request);
  char *status = ipfs_node_status(handle);
  char *capabilities = ipfs_node_capabilities(handle);

  if (result == IPFS_NODE_OK) {
    ipfs_node_stop(handle);
  }
  ipfs_node_free_string(status);
  ipfs_node_free_string(capabilities);
  ipfs_node_free(handle);
}
