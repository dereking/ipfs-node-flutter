// ipfs_node_core exposes the foundation lifecycle over a small C ABI.
package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"sync"
	"time"
	"unsafe"

	"github.com/dereking/ipfs-node-flutter/native/go/internal/core"
)

const (
	errOK C.int = iota
	errInvalidHandle
	errInvalidConfiguration
	errInvalidState
	errNodeAlreadyRunning
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
	Network             string   `json:"network"`
	SwarmKey            []byte   `json:"swarmKey,omitempty"`
	BootstrapPeers      []string `json:"bootstrapPeers,omitempty"`
	UseDefaultBootstrap bool     `json:"useDefaultBootstrap,omitempty"`
	RepositoryPath      string   `json:"repositoryPath,omitempty"`
	RelayPeers          []string `json:"relayPeers,omitempty"`
	AllowedPeerIDs      []string `json:"allowedPeerIds,omitempty"`
}

type blockResponse struct {
	Data  string `json:"data,omitempty"`
	Error string `json:"error,omitempty"`
}

type addResponse struct {
	Cid   string `json:"cid,omitempty"`
	Bytes int    `json:"bytes,omitempty"`
	Error string `json:"error,omitempty"`
}

type operationResponse struct {
	Error string `json:"error,omitempty"`
}

type nameResponse struct {
	Name  string `json:"name,omitempty"`
	Path  string `json:"path,omitempty"`
	Error string `json:"error,omitempty"`
}

func stringResponse(operation string, fn func() (any, error)) *C.char {
	value, err := fn()
	if err != nil {
		return jsonString(operationResponse{Error: err.Error()})
	}
	return jsonString(value)
}

func stringOperation(operation string, fn func() error) *C.char {
	if err := fn(); err != nil {
		return jsonString(operationResponse{Error: err.Error()})
	}
	return jsonString(operationResponse{})
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
// It returns zero on success; see include/ipfs_node_core.h for stable codes.
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
		if errors.Is(err, core.ErrNodeAlreadyRunning) {
			return errNodeAlreadyRunning
		}
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

// ipfs_node_capabilities returns a heap-allocated JSON capability array.
//
//export ipfs_node_capabilities
func ipfs_node_capabilities(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return jsonString(node.Capabilities())
}

// ipfs_node_get_block retrieves a verified raw IPFS block and returns a
// heap-allocated JSON object containing base64 data or an error message.
// Call ipfs_node_free_string exactly once for non-NULL results.
//
//export ipfs_node_get_block
func ipfs_node_get_block(handle C.uintptr_t, cid *C.char, timeout_millis C.int) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if cid == nil || timeout_millis <= 0 {
		return jsonString(blockResponse{Error: "invalid block request"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout_millis)*time.Millisecond)
	defer cancel()
	data, err := node.GetBlock(ctx, C.GoString(cid))
	if err != nil {
		return jsonString(blockResponse{Error: err.Error()})
	}
	return jsonString(blockResponse{Data: base64.StdEncoding.EncodeToString(data)})
}

// ipfs_node_add_bytes stores raw bytes as a UnixFS file and returns a
// heap-allocated JSON object containing the content root CID or an error.
// Call ipfs_node_free_string exactly once for non-NULL results.
//
//export ipfs_node_add_bytes
func ipfs_node_add_bytes(handle C.uintptr_t, data unsafe.Pointer, length C.size_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if data == nil {
		return jsonString(addResponse{Error: "invalid add request"})
	}
	cid, err := node.AddBytes(context.Background(), C.GoBytes(data, C.int(length)))
	if err != nil {
		return jsonString(addResponse{Error: err.Error()})
	}
	return jsonString(addResponse{Cid: cid, Bytes: int(length)})
}

//export ipfs_node_network_ready
func ipfs_node_network_ready(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return jsonString(map[string]bool{"ready": node.NetworkReady()})
}

//export ipfs_node_provide
func ipfs_node_provide(handle C.uintptr_t, rawCID *C.char, timeoutMillis C.int) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawCID == nil || timeoutMillis <= 0 {
		return jsonString(operationResponse{Error: "invalid provide request"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMillis)*time.Millisecond)
	defer cancel()
	return stringOperation("provide", func() error { return node.Provide(ctx, C.GoString(rawCID)) })
}

//export ipfs_node_add_and_provide
func ipfs_node_add_and_provide(handle C.uintptr_t, data unsafe.Pointer, length C.size_t, timeoutMillis C.int) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if data == nil || timeoutMillis <= 0 {
		return jsonString(addResponse{Error: "invalid add and provide request"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMillis)*time.Millisecond)
	defer cancel()
	cid, err := node.AddAndProvide(ctx, C.GoBytes(data, C.int(length)))
	if err != nil {
		return jsonString(addResponse{Cid: cid, Bytes: int(length), Error: err.Error()})
	}
	return jsonString(addResponse{Cid: cid, Bytes: int(length)})
}

//export ipfs_node_start_providing
func ipfs_node_start_providing(handle C.uintptr_t, rawCID *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawCID == nil {
		return jsonString(operationResponse{Error: "invalid start providing request"})
	}
	return stringOperation("start providing", func() error {
		return node.StartProviding(context.Background(), C.GoString(rawCID))
	})
}

//export ipfs_node_publication_status
func ipfs_node_publication_status(handle C.uintptr_t, rawCID *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawCID == nil {
		return jsonString(operationResponse{Error: "invalid publication status request"})
	}
	return stringResponse("publication status", func() (any, error) {
		return node.PublicationStatus(C.GoString(rawCID))
	})
}

//export ipfs_node_list_publication_statuses
func ipfs_node_list_publication_statuses(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return stringResponse("list publication statuses", func() (any, error) {
		return node.ListPublicationStatuses()
	})
}

// ipfs_node_pin ensures a content root is local and pinned. Returns a
// heap-allocated JSON object with an optional error.
//
//export ipfs_node_pin
func ipfs_node_pin(handle C.uintptr_t, rawCID *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawCID == nil {
		return jsonString(operationResponse{Error: "invalid pin request"})
	}
	if err := node.Pin(context.Background(), C.GoString(rawCID)); err != nil {
		return jsonString(operationResponse{Error: err.Error()})
	}
	return jsonString(operationResponse{})
}

// ipfs_node_unpin removes a content root from the local pin set.
//
//export ipfs_node_unpin
func ipfs_node_unpin(handle C.uintptr_t, rawCID *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawCID == nil {
		return jsonString(operationResponse{Error: "invalid unpin request"})
	}
	if err := node.Unpin(C.GoString(rawCID)); err != nil {
		return jsonString(operationResponse{Error: err.Error()})
	}
	return jsonString(operationResponse{})
}

// ipfs_node_list_pins returns a heap-allocated JSON array of pinned content
// roots, or an object containing an error.
//
//export ipfs_node_list_pins
func ipfs_node_list_pins(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	pins, err := node.ListPins()
	if err != nil {
		return jsonString(operationResponse{Error: err.Error()})
	}
	return jsonString(pins)
}

// ipfs_node_swarm_peers returns a heap-allocated JSON array of connected peers.
//
//export ipfs_node_swarm_peers
func ipfs_node_swarm_peers(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return stringResponse("swarm_peers", func() (any, error) {
		return node.SwarmPeers()
	})
}

// ipfs_node_swarm_connect dials a p2p multiaddr.
//
//export ipfs_node_swarm_connect
func ipfs_node_swarm_connect(handle C.uintptr_t, multiaddr *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if multiaddr == nil {
		return jsonString(operationResponse{Error: "invalid connect request"})
	}
	return stringOperation("swarm_connect", func() error {
		return node.SwarmConnect(context.Background(), C.GoString(multiaddr))
	})
}

// ipfs_node_swarm_disconnect closes connections to a peer.
//
//export ipfs_node_swarm_disconnect
func ipfs_node_swarm_disconnect(handle C.uintptr_t, peerID *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if peerID == nil {
		return jsonString(operationResponse{Error: "invalid disconnect request"})
	}
	return stringOperation("swarm_disconnect", func() error {
		return node.SwarmDisconnect(C.GoString(peerID))
	})
}

// ipfs_node_bootstrap_list returns the configured bootstrap multiaddrs.
//
//export ipfs_node_bootstrap_list
func ipfs_node_bootstrap_list(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return stringResponse("bootstrap_list", func() (any, error) {
		return node.BootstrapList()
	})
}

// ipfs_node_bootstrap_add records a bootstrap multiaddr.
//
//export ipfs_node_bootstrap_add
func ipfs_node_bootstrap_add(handle C.uintptr_t, multiaddr *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if multiaddr == nil {
		return jsonString(operationResponse{Error: "invalid bootstrap request"})
	}
	return stringOperation("bootstrap_add", func() error {
		return node.BootstrapAdd(C.GoString(multiaddr))
	})
}

// ipfs_node_bootstrap_remove removes a bootstrap multiaddr.
//
//export ipfs_node_bootstrap_remove
func ipfs_node_bootstrap_remove(handle C.uintptr_t, multiaddr *C.char) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if multiaddr == nil {
		return jsonString(operationResponse{Error: "invalid bootstrap request"})
	}
	return stringOperation("bootstrap_remove", func() error {
		return node.BootstrapRemove(C.GoString(multiaddr))
	})
}

// ipfs_node_bitswap_stats returns current bitswap counters.
//
//export ipfs_node_bitswap_stats
func ipfs_node_bitswap_stats(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return stringResponse("bitswap_stats", func() (any, error) {
		return node.BitswapStats()
	})
}

// ipfs_node_find_providers searches the DHT for content providers.
//
//export ipfs_node_find_providers
func ipfs_node_find_providers(handle C.uintptr_t, rawCID *C.char, timeout_millis C.int) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawCID == nil || timeout_millis <= 0 {
		return jsonString(operationResponse{Error: "invalid find providers request"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout_millis)*time.Millisecond)
	defer cancel()
	return stringResponse("find_providers", func() (any, error) {
		return node.FindProviders(ctx, C.GoString(rawCID))
	})
}

// ipfs_node_find_peer locates a peer on the DHT.
//
//export ipfs_node_find_peer
func ipfs_node_find_peer(handle C.uintptr_t, peerID *C.char, timeout_millis C.int) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if peerID == nil || timeout_millis <= 0 {
		return jsonString(operationResponse{Error: "invalid find peer request"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout_millis)*time.Millisecond)
	defer cancel()
	return stringResponse("find_peer", func() (any, error) {
		return node.FindPeer(ctx, C.GoString(peerID))
	})
}

// ipfs_node_publish_name publishes a content root under the node's IPNS name.
//
//export ipfs_node_publish_name
func ipfs_node_publish_name(handle C.uintptr_t, rawCID *C.char, timeout_millis C.int) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawCID == nil || timeout_millis <= 0 {
		return jsonString(nameResponse{Error: "invalid publish request"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout_millis)*time.Millisecond)
	defer cancel()
	name, err := node.PublishName(ctx, C.GoString(rawCID))
	if err != nil {
		return jsonString(nameResponse{Error: err.Error()})
	}
	return jsonString(nameResponse{Name: name})
}

// ipfs_node_resolve_name resolves an IPNS name to a content path.
//
//export ipfs_node_resolve_name
func ipfs_node_resolve_name(handle C.uintptr_t, rawName *C.char, timeout_millis C.int) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	if rawName == nil || timeout_millis <= 0 {
		return jsonString(nameResponse{Error: "invalid resolve request"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout_millis)*time.Millisecond)
	defer cancel()
	path, err := node.ResolveName(ctx, C.GoString(rawName))
	if err != nil {
		return jsonString(nameResponse{Error: err.Error()})
	}
	return jsonString(nameResponse{Path: path})
}

// ipfs_node_list_keys returns the local IPNS keys.
//
//export ipfs_node_list_keys
func ipfs_node_list_keys(handle C.uintptr_t) *C.char {
	node, ok := lookup(handle)
	if !ok {
		return nil
	}
	return stringResponse("list_keys", func() (any, error) {
		return node.ListKeys()
	})
}

// ipfs_node_free invalidates an opaque node handle. Repeated frees are safe.
//
//export ipfs_node_free
func ipfs_node_free(handle C.uintptr_t) {
	registry.Lock()
	node := registry.nodes[handle]
	delete(registry.nodes, handle)
	registry.Unlock()
	if node != nil {
		_ = node.Stop()
	}
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
		if request.UseDefaultBootstrap && len(request.BootstrapPeers) == 0 {
			request.BootstrapPeers = core.DefaultPublicBootstrapPeers()
		}
		return core.PublicConfig{
			BootstrapPeers: request.BootstrapPeers,
			RepositoryPath: request.RepositoryPath,
		}, nil
	case "private":
		return core.PrivateConfig{
			RepositoryPath: request.RepositoryPath,
			SwarmKey:       request.SwarmKey,
			BootstrapPeers: request.BootstrapPeers,
			RelayPeers:     request.RelayPeers,
			AllowedPeerIDs: request.AllowedPeerIDs,
		}, nil
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
