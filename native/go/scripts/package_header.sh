#!/bin/sh
set -eu

header="$1"
generated="${header}.generated"

mv "$header" "$generated"
trap 'rm -f "$generated"' EXIT

for declaration in \
  'extern uintptr_t ipfs_node_create(void);' \
  'extern int ipfs_node_start(uintptr_t handle, char* request);' \
  'extern int ipfs_node_stop(uintptr_t handle);' \
  'extern char* ipfs_node_status(uintptr_t handle);' \
  'extern char* ipfs_node_capabilities(uintptr_t handle);' \
  'extern char* ipfs_node_get_block(uintptr_t handle, char* cid, int timeout_millis);' \
  'extern void ipfs_node_free(uintptr_t handle);' \
  'extern void ipfs_node_free_string(char* value);'
do
  if ! grep -Fqx "$declaration" "$generated"; then
    echo "generated C ABI header is missing: $declaration" >&2
    exit 1
  fi
done

{
  echo '/* Packaged IPFS node C ABI. Generated declarations follow. */'
  echo '#ifndef IPFS_NODE_CORE_H'
  echo '#define IPFS_NODE_CORE_H'
  echo
  echo '/* Stable return codes for ipfs_node_start and ipfs_node_stop. */'
  echo '#define IPFS_NODE_OK 0'
  echo '#define IPFS_NODE_ERR_INVALID_HANDLE 1'
  echo '#define IPFS_NODE_ERR_INVALID_CONFIGURATION 2'
  echo '#define IPFS_NODE_ERR_INVALID_STATE 3'
  echo '#define IPFS_NODE_ERR_NODE_ALREADY_RUNNING 4'
  echo
  sed 's/^/ /' "$generated"
  echo
  echo '#endif /* IPFS_NODE_CORE_H */'
} > "$header"

rm -f "$generated"
trap - EXIT
