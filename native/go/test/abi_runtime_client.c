#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "libipfs_node_core.h"

int main(void) {
  char repository_path[256];
  snprintf(repository_path, sizeof(repository_path), "/tmp/ipfs-node-abi-%d",
           (int)getpid());
  if (mkdir(repository_path, 0700) != 0) {
    return 10;
  }
  char public_request[512];
  snprintf(public_request, sizeof(public_request),
           "{\"network\":\"public\",\"repositoryPath\":\"%s\"}",
           repository_path);
  char invalid_private_request[] =
      "{\"network\":\"private\",\"swarmKey\":\"\"}";
  char private_repository_path[256];
  snprintf(private_repository_path, sizeof(private_repository_path),
           "/tmp/ipfs-node-private-abi-%d", (int)getpid());
  if (mkdir(private_repository_path, 0700) != 0) {
    return 11;
  }
  char private_request[768];
  snprintf(private_request, sizeof(private_request),
           "{\"network\":\"private\",\"repositoryPath\":\"%s\","
           "\"swarmKey\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"}",
           private_repository_path);

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
  if (ipfs_node_start(handle, private_request) != IPFS_NODE_OK) {
    return 12;
  }
  capabilities = ipfs_node_capabilities(handle);
  if (capabilities == NULL ||
      strstr(capabilities, "\"privateSwarmKey\"") == NULL ||
      strstr(capabilities, "\"providerRouting\"") == NULL ||
      strstr(capabilities, "\"publicPublication\"") != NULL) {
    return 13;
  }
  ipfs_node_free_string(capabilities);
  if (ipfs_node_stop(handle) != IPFS_NODE_OK) {
    return 14;
  }
  ipfs_node_free(handle);
  if (ipfs_node_stop(handle) != IPFS_NODE_ERR_INVALID_HANDLE) {
    return 9;
  }
  return 0;
}
