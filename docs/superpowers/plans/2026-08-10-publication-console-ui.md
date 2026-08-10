# IPFS Publication Console UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement task-by-task with tests first.

**Goal:** Add an explicit local-storage and public-publication console to the Flutter IPFS example.

**Architecture:** Reusable UI cards call the existing `IpfsNodeController` API. Native capability and network state decide whether public actions are enabled; Web receives explicit unsupported messaging.

**Tech Stack:** Flutter Material 3, `ipfs_node_flutter` UI/controller, widget tests.

### Task 1: Network diagnostics card

**Files:** create `packages/ipfs_node_flutter/lib/ui/ipfs_publication_status_panel.dart`; modify `lib/ui/ipfs_node_ui.dart`; test `packages/ipfs_node_flutter/test/ui_test.dart`.

- [ ] Write a widget test expecting DHT, relay/direct reachability, ready state and an unavailable reason.
- [ ] Run `flutter test packages/ipfs_node_flutter/test/ui_test.dart` and confirm RED.
- [ ] Implement a status card that renders `NodeStatus`, `networkReady`, and a typed unsupported explanation.
- [ ] Re-run the focused test and commit `feat: show IPFS publication readiness`.

### Task 2: Local add versus add-and-publish controls

**Files:** modify `packages/ipfs_node_flutter/lib/ui/ipfs_content_add_panel.dart`; test `packages/ipfs_node_flutter/test/ui_test.dart`.

- [ ] Write widget tests for distinct local add and publish actions, including a disabled/failed publish state.
- [ ] Confirm RED, then add a secondary local button and primary `addAndProvide` button with result/error state.
- [ ] Re-run focused tests and commit `feat: add explicit IPFS publish action`.

### Task 3: CID/repository/external verification cards

**Files:** create `ipfs_cid_publication_panel.dart`, `ipfs_repository_panel.dart`, `ipfs_kubo_verify_panel.dart`; modify exports and `example/lib/main.dart`; test UI package and example.

- [ ] Add failing widget tests for provider lookup/retry, repository summary, and Web-disabled Kubo verification.
- [ ] Implement native-capability-gated cards and add them to the example feature tab.
- [ ] Run `flutter test` and `flutter analyze` for the UI package and example; commit `feat: add IPFS publication console`.
