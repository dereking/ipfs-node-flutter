package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/dereking/ipfs-node-flutter/native/go/internal/core"
)

type message struct {
	Type   string   `json:"type"`
	CID    string   `json:"cid,omitempty"`
	Data   string   `json:"data,omitempty"`
	Error  string   `json:"error,omitempty"`
	PeerID string   `json:"peerId,omitempty"`
	Addrs  []string `json:"addrs,omitempty"`
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: private-test-peer <repository> <base64-psk>")
		os.Exit(2)
	}
	key, err := base64.StdEncoding.DecodeString(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	node := core.New()
	if err := node.Start(core.PrivateConfig{RepositoryPath: os.Args[1], SwarmKey: key}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(3)
	}
	defer node.Stop()

	status := node.Status()
	addrs := loopbackAddrs(status.ListenAddrs)
	if len(addrs) == 0 {
		addrs = status.ListenAddrs
	}
	encoder := json.NewEncoder(os.Stdout)
	if err := encoder.Encode(message{Type: "ready", PeerID: status.PeerID, Addrs: addrs}); err != nil {
		os.Exit(4)
	}

	decoder := json.NewDecoder(bufio.NewReader(os.Stdin))
	for {
		var request message
		if err := decoder.Decode(&request); err != nil {
			return
		}
		if request.Type != "get" {
			_ = encoder.Encode(message{Type: "error", Error: "unsupported request"})
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		data, err := node.GetBlock(ctx, request.CID)
		cancel()
		if err != nil {
			_ = encoder.Encode(message{Type: "content", CID: request.CID, Error: err.Error()})
			continue
		}
		_ = encoder.Encode(message{
			Type: "content",
			CID:  request.CID,
			Data: base64.StdEncoding.EncodeToString(data),
		})
	}
}

func loopbackAddrs(addrs []string) []string {
	result := make([]string, 0, len(addrs))
	for _, addr := range addrs {
		if strings.Contains(addr, "/ip4/127.0.0.1/") || strings.Contains(addr, "/ip6/::1/") {
			result = append(result, addr)
		}
	}
	return result
}
