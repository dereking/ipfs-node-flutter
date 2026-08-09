#ifndef IPFS_NODE_CORE_H
#define IPFS_NODE_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Stable return codes for ipfs_node_start and ipfs_node_stop. */
#define IPFS_NODE_OK 0
#define IPFS_NODE_ERR_INVALID_HANDLE 1
#define IPFS_NODE_ERR_INVALID_CONFIGURATION 2
#define IPFS_NODE_ERR_INVALID_STATE 3

/* Creates a stopped node and returns an opaque handle. */
uintptr_t ipfs_node_create(void);

/*
 * Starts a node from JSON: {"network":"public"} or
 * {"network":"private","swarmKey":"<base64>"}. The caller retains
 * ownership of request.
 */
int ipfs_node_start(uintptr_t handle, char *request);

/* Stops a node. */
int ipfs_node_stop(uintptr_t handle);

/*
 * Returns heap-allocated JSON, or NULL for an invalid handle. Free every
 * non-NULL result with ipfs_node_free_string.
 */
char *ipfs_node_status(uintptr_t handle);
char *ipfs_node_capabilities(uintptr_t handle);

/* Invalidates a node handle; repeated calls are safe. */
void ipfs_node_free(uintptr_t handle);

/* Frees a string returned by ipfs_node_status or ipfs_node_capabilities. */
void ipfs_node_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
