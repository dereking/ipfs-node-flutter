package core

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/ipfs/boxo/blockstore"
	leveldb "github.com/ipfs/go-ds-leveldb"
	"github.com/libp2p/go-libp2p/core/crypto"
)

const (
	repositoryMetadataFile = "metadata.json"
	repositoryIdentityFile = "identity.key"
)

type repositoryMetadata struct {
	Pins  map[string]PinInfo         `json:"pins"`
	Roots map[string]contentMetadata `json:"roots"`
}

type contentMetadata struct {
	AddedAt       time.Time  `json:"addedAt"`
	LastPublished *time.Time `json:"lastPublished,omitempty"`
	PublishError  string     `json:"publishError,omitempty"`
}

type repository struct {
	mu        sync.Mutex
	path      string
	datastore *leveldb.Datastore
	store     blockstore.Blockstore
	metadata  repositoryMetadata
}

func openRepository(path string) (*repository, error) {
	if path == "" {
		return nil, ErrRepositoryPathRequired
	}
	if err := os.MkdirAll(path, 0o700); err != nil {
		return nil, err
	}
	datastore, err := leveldb.NewDatastore(filepath.Join(path, "blocks"), nil)
	if err != nil {
		return nil, ErrRepositoryLocked
	}
	repo := &repository{
		path:      path,
		datastore: datastore,
		store:     blockstore.NewBlockstore(datastore),
		metadata: repositoryMetadata{
			Pins:  make(map[string]PinInfo),
			Roots: make(map[string]contentMetadata),
		},
	}
	if err := repo.loadMetadata(); err != nil {
		_ = datastore.Close()
		return nil, err
	}
	return repo, nil
}

func (repo *repository) loadMetadata() error {
	encoded, err := os.ReadFile(filepath.Join(repo.path, repositoryMetadataFile))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if err := json.Unmarshal(encoded, &repo.metadata); err != nil {
		return err
	}
	if repo.metadata.Pins == nil {
		repo.metadata.Pins = make(map[string]PinInfo)
	}
	if repo.metadata.Roots == nil {
		repo.metadata.Roots = make(map[string]contentMetadata)
	}
	return nil
}

func (repo *repository) saveMetadata() error {
	encoded, err := json.Marshal(repo.metadata)
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(repo.path, "metadata-*")
	if err != nil {
		return err
	}
	name := temporary.Name()
	defer os.Remove(name)
	if _, err := temporary.Write(encoded); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Chmod(0o600); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(name, filepath.Join(repo.path, repositoryMetadataFile))
}

func (repo *repository) loadOrCreateIdentity() (crypto.PrivKey, error) {
	path := filepath.Join(repo.path, repositoryIdentityFile)
	encoded, err := os.ReadFile(path)
	if err == nil {
		return crypto.UnmarshalPrivateKey(encoded)
	}
	if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	key, _, err := crypto.GenerateKeyPair(crypto.Ed25519, -1)
	if err != nil {
		return nil, err
	}
	encoded, err = crypto.MarshalPrivateKey(key)
	if err != nil {
		return nil, err
	}
	return key, os.WriteFile(path, encoded, 0o600)
}

func (repo *repository) recordRoot(cid string) error {
	repo.mu.Lock()
	defer repo.mu.Unlock()
	if _, ok := repo.metadata.Roots[cid]; !ok {
		repo.metadata.Roots[cid] = contentMetadata{AddedAt: time.Now().UTC()}
	}
	return repo.saveMetadata()
}

func (repo *repository) setPins(pins map[string]PinInfo) error {
	repo.mu.Lock()
	defer repo.mu.Unlock()
	repo.metadata.Pins = make(map[string]PinInfo, len(pins))
	for cid, pin := range pins {
		repo.metadata.Pins[cid] = pin
	}
	return repo.saveMetadata()
}

func (repo *repository) recordPublication(cid string, publishedAt time.Time, publishError string) error {
	repo.mu.Lock()
	defer repo.mu.Unlock()
	entry := repo.metadata.Roots[cid]
	entry.LastPublished = &publishedAt
	entry.PublishError = publishError
	repo.metadata.Roots[cid] = entry
	return repo.saveMetadata()
}

func (repo *repository) Close() error {
	return repo.datastore.Close()
}
