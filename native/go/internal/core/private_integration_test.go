package core

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

type helperMessage struct {
	Type   string   `json:"type"`
	CID    string   `json:"cid,omitempty"`
	Data   string   `json:"data,omitempty"`
	Error  string   `json:"error,omitempty"`
	PeerID string   `json:"peerId,omitempty"`
	Addrs  []string `json:"addrs,omitempty"`
}

func TestPrivateNetworkAcrossProcesses(t *testing.T) {
	key := bytes.Repeat([]byte{23}, 32)
	binary := filepath.Join(t.TempDir(), "private-test-peer")
	build := exec.Command("go", "build", "-o", binary, "./internal/core/testhelper")
	build.Dir = filepath.Join("..", "..")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build helper: %v\n%s", err, output)
	}

	helper := exec.Command(binary, t.TempDir(), base64.StdEncoding.EncodeToString(key))
	stdin, err := helper.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := helper.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := helper.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = stdin.Close()
		_ = helper.Process.Kill()
		_ = helper.Wait()
	})

	decoder := json.NewDecoder(bufio.NewReader(stdout))
	var ready helperMessage
	if err := decoder.Decode(&ready); err != nil {
		t.Fatal(err)
	}
	if ready.Type != "ready" || len(ready.Addrs) == 0 {
		t.Fatalf("helper readiness = %+v", ready)
	}

	parent := New()
	if err := parent.Start(PrivateConfig{
		RepositoryPath: t.TempDir(),
		SwarmKey:       key,
		BootstrapPeers: ready.Addrs,
	}); err != nil {
		t.Fatal(err)
	}
	content := []byte("private process integration\n")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	for !parent.NetworkReady() {
		select {
		case <-ctx.Done():
			t.Fatalf("private network not ready: %+v", parent.Status())
		case <-time.After(50 * time.Millisecond):
		}
	}
	rawCID, err := parent.AddAndProvide(ctx, content)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.NewEncoder(stdin).Encode(helperMessage{Type: "get", CID: rawCID}); err != nil {
		t.Fatal(err)
	}
	var fetched helperMessage
	if err := decoder.Decode(&fetched); err != nil {
		t.Fatal(err)
	}
	if fetched.Error != "" {
		t.Fatal(fetched.Error)
	}
	decoded, err := base64.StdEncoding.DecodeString(fetched.Data)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(decoded, content) {
		t.Fatalf("retrieved %q, want %q", decoded, content)
	}
	if err := parent.Stop(); err != nil {
		t.Fatal(err)
	}

	mismatched := New()
	if err := mismatched.Start(PrivateConfig{
		RepositoryPath: t.TempDir(),
		SwarmKey:       bytes.Repeat([]byte{24}, 32),
		BootstrapPeers: ready.Addrs,
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = mismatched.Stop() })
	if mismatched.NetworkReady() || len(mismatched.Status().ConnectedPeers) != 0 {
		t.Fatalf("mismatched PSK connected: %+v", mismatched.Status())
	}
}
