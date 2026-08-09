// ipfs_node_core exposes the foundation lifecycle over a small C ABI.
package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"sync"
	"unsafe"

	"github.com/dereking/ipfs-node-flutter/native/go/internal/core"
)

const (
	errOK C.int = iota
	errInvalidHandle
	errInvalidConfiguration
	errInvalidState
)

var registry = struct {
	sync.Mutex
	next  C.uintptr_t
	nodes map[C.uintptr_t]*core.Core
}{
	next:  1,
	nodes: make(map[C.uintptr_t]*core.Core),
}

type startRequest struct {
	Network  string `json:"network"`
	SwarmKey []byte `json:"swarmKey,omitempty"`
}

// ipfs_node_create creates a stopped node and returns its opaque handle.
//
//export ipfs_node_create
func ipfs_node_create() C.uintptr_t {
	registry.Lock()
	defer registry.Unlock()

	handle := registry.next
	registry.next++
	registry.nodes[handle] = core.New()
	return handle
}

// ipfs_node_start starts a node from a JSON request. The request is either
// {"network":"public"} or {"network":"private","swarmKey":"<base64>"}.
// It returns zero on success; see the err* constants for non-zero values.
//
//export ipfs_node_start
func ipfs_node_start(handle C.uintptr_t, request *C.char) C.int {
	node, ok := lookup(handle)
	if !ok {
		return errInvalidHandle
	}

	config, err := parseStartRequest(request)
	if err != nil {
		return errInvalidConfiguration
	}
	if err := node.Start(config); err != nil {
		if errors.Is(err, core.ErrInvalidLifecycleTransition) {
			return errInvalidState
		}
		return errInvalidConfiguration
	}
	return errOK
}

// ipfs_node_stop stops a node. It returns zero on success.
//
//export ipfs_node_stop
func ipfs_node_stop(handle C.uintptr_t) C.int {
	node, ok := lookup(handle)
	if !ok {
		return errInvalidHandle
	}
	if err := node.Stop(); err != nil {
		return errInvalidState
	}
	return errOK
}

// ipfs_node_status returns a heap-allocated JSON status string, or NULL for
// an invalid handle. Call ipfs_node_free_string exactly once for non-NULL
// results.
//
//export ipfs_node_status
func ipfs_node_status(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return jsonString(node.Status())
}

// ipfs_node_capabilities returns a heap-allocated JSON array. Foundation
// nodes deliberately report no transport or protocol capabilities.
//
//export ipfs_node_capabilities
func ipfs_node_capabilities(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return jsonString(node.Capabilities())
}

// ipfs_node_free invalidates an opaque node handle. Repeated frees are safe.
//
//export ipfs_node_free
func ipfs_node_free(handle C.uintptr_t) {
	registry.Lock()
	defer registry.Unlock()
	delete(registry.nodes, handle)
}

// ipfs_node_free_string frees strings allocated by status or capabilities.
//
//export ipfs_node_free_string
func ipfs_node_free_string(value *C.char) {
	C.free(unsafe.Pointer(value))
}

func lookup(handle C.uintptr_t) (*core.Core, bool) {
	registry.Lock()
	defer registry.Unlock()
	node, ok := registry.nodes[handle]
	return node, ok
}

func parseStartRequest(value *C.char) (any, error) {
	if value == nil {
		return nil, errors.New("missing start request")
	}

	var request startRequest
	if err := json.Unmarshal([]byte(C.GoString(value)), &request); err != nil {
		return nil, err
	}
	switch request.Network {
	case "public":
		return core.PublicConfig{}, nil
	case "private":
		return core.PrivateConfig{SwarmKey: request.SwarmKey}, nil
	default:
		return nil, errors.New("unsupported network")
	}
}

func jsonString(value any) *C.char {
	encoded, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	return C.CString(string(encoded))
}

func main() {}
