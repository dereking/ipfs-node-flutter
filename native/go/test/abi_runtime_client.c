#include <stdio.h>
#include <string.h>

#include "libipfs_node_core.h"

int main(void) {
  char public_request[] = "{\"network\":\"public\"}";
  char invalid_private_request[] =
      "{\"network\":\"private\",\"swarmKey\":\"\"}";

  if (ipfs_node_start(0, public_request) != IPFS_NODE_ERR_INVALID_HANDLE) {
    return 1;
  }

  uintptr_t handle = ipfs_node_create();
  if (handle == 0) {
    return 2;
  }
  if (ipfs_node_start(handle, invalid_private_request) !=
      IPFS_NODE_ERR_INVALID_CONFIGURATION) {
    return 3;
  }
  if (ipfs_node_start(handle, public_request) != IPFS_NODE_OK) {
    return 4;
  }

  char *status = ipfs_node_status(handle);
  char *capabilities = ipfs_node_capabilities(handle);
  if (status == NULL || strstr(status, "\"running\"") == NULL) {
    return 5;
  }
  if (capabilities == NULL ||
      strstr(capabilities, "\"inboundListen\"") == NULL ||
      strstr(capabilities, "\"tcp\"") == NULL ||
      strstr(capabilities, "\"quic\"") == NULL ||
      strstr(capabilities, "\"dhtRouting\"") == NULL) {
    return 6;
  }
  ipfs_node_free_string(status);
  ipfs_node_free_string(capabilities);

  char invalid_cid[] = "not-a-cid";
  char *block = ipfs_node_get_block(handle, invalid_cid, 1000);
  if (block == NULL || strstr(block, "\"error\"") == NULL) {
    return 7;
  }
  ipfs_node_free_string(block);

  if (ipfs_node_stop(handle) != IPFS_NODE_OK) {
    return 8;
  }
  ipfs_node_free(handle);
  if (ipfs_node_stop(handle) != IPFS_NODE_ERR_INVALID_HANDLE) {
    return 9;
  }
  return 0;
}
