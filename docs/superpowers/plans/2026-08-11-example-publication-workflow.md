# Example Publication Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Link newly added durable CIDs directly into the Example publication controls while disabling unsupported web publication.

**Architecture:** Extend the existing reusable add panel with a small result callback and capability flag, and make the existing publication panel respond to changed initial CIDs. Keep selected-CID state in the Example presentation layer so the SDK and network semantics remain unchanged.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing `ipfs_node_flutter` widgets and platform interface.

---

## File map

- Modify `packages/ipfs_node_flutter/lib/ui/ipfs_content_add_panel.dart`: expose durable add results and disable unsupported publication.
- Modify `packages/ipfs_node_flutter/lib/ui/ipfs_cid_publication_panel.dart`: accept a newly selected CID after initial build.
- Modify `packages/ipfs_node_flutter/test/ui_test.dart`: test callback, failure, unsupported capability, and CID updates.
- Modify `example/lib/pages/content_repository_page.dart`: retain and hand off the latest durable CID.
- Modify `example/lib/main.dart`: connect the legacy feature-lab add and publication panels.
- Modify `example/test/complete_example_test.dart` and `example/test/widget_test.dart`: assert both Example entry points expose the linked controls.

### Task 1: Shared add-panel result and capability contract

**Files:**
- Modify: `packages/ipfs_node_flutter/test/ui_test.dart`
- Modify: `packages/ipfs_node_flutter/lib/ui/ipfs_content_add_panel.dart`

- [ ] **Step 1: Write failing callback and unsupported-publication widget tests**

Add tests that capture the callback result:

```dart
testWidgets('IpfsContentAddPanel reports every durable CID', (tester) async {
  final controller = IpfsNodeController();
  addTearDown(controller.dispose);
  IpfsAddResult? selected;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: IpfsContentAddPanel(
        controller: controller,
        onAdded: (result) => selected = result,
      ),
    ),
  ));
  await tester.enterText(find.byType(TextField), 'some text');
  await tester.tap(find.text('本地添加'));
  await tester.pumpAndSettle();
  expect(selected?.cid, 'bafkrei-added-9');
});

testWidgets('IpfsContentAddPanel disables unsupported publication',
    (tester) async {
  final controller = IpfsNodeController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: IpfsContentAddPanel(
        controller: controller,
        publicationSupported: false,
      ),
    ),
  ));
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, '添加并发布'),
  );
  expect(button.onPressed, isNull);
  expect(find.textContaining('当前平台不支持公网发布'), findsOneWidget);
});
```

Extend the fake backend with `bool failPublication = false`; when true,
`addAndProvide` throws `IpfsPublicationException` carrying
`IpfsAddResult(cid: 'bafkrei-durable', bytes: bytes.length)`. Add a third test
asserting `onAdded` receives that result after tapping `添加并发布`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```sh
flutter test test/ui_test.dart --plain-name 'IpfsContentAddPanel reports every durable CID'
```

Expected: compilation fails because `onAdded` is not defined. Run the other two
new names after the first compiles; expect failures because the capability flag
and exception callback are missing.

- [ ] **Step 3: Implement the minimal add-panel contract**

Add fields and defaults:

```dart
final bool publicationSupported;
final ValueChanged<IpfsAddResult>? onAdded;
```

Invoke `onAdded` after successful local/strict add and inside the
`IpfsPublicationException` branch. Disable the strict button when
`!publicationSupported` and render `当前平台不支持公网发布；仍可本地添加和读取`.

- [ ] **Step 4: Run the add-panel tests and verify GREEN**

Run:

```sh
flutter test test/ui_test.dart
```

Expected: all UI tests pass.

### Task 2: Publication panel accepts the latest CID

**Files:**
- Modify: `packages/ipfs_node_flutter/test/ui_test.dart`
- Modify: `packages/ipfs_node_flutter/lib/ui/ipfs_cid_publication_panel.dart`

- [ ] **Step 1: Write the failing widget-update test**

```dart
testWidgets('IpfsCidPublicationPanel follows a newly added CID',
    (tester) async {
  final controller = IpfsNodeController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: IpfsCidPublicationPanel(
      controller: controller,
      initialCid: 'bafkrei-first',
    ),
  ));
  await tester.pumpWidget(MaterialApp(
    home: IpfsCidPublicationPanel(
      controller: controller,
      initialCid: 'bafkrei-second',
    ),
  ));
  final field = tester.widget<TextField>(find.byType(TextField));
  expect(field.controller?.text, 'bafkrei-second');
});
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```sh
flutter test test/ui_test.dart --plain-name 'IpfsCidPublicationPanel follows a newly added CID'
```

Expected: FAIL because the controller still contains `bafkrei-first`.

- [ ] **Step 3: Implement CID synchronization**

Override `didUpdateWidget`. When the non-empty `initialCid` changes, assign it
to `_cid.text`. Do not clear manually entered text when the parent supplies
`null`.

- [ ] **Step 4: Run the focused and full UI tests**

Run `flutter test test/ui_test.dart`.

Expected: all tests pass.

### Task 3: Wire both Example entry points

**Files:**
- Modify: `example/lib/pages/content_repository_page.dart`
- Modify: `example/lib/main.dart`
- Modify: `example/test/complete_example_test.dart`
- Modify: `example/test/widget_test.dart`

- [ ] **Step 1: Write failing Example handoff tests**

Add a minimal `_ExampleFakePlatform` implementing lifecycle methods and
returning `IpfsAddResult(cid: 'bafkrei-example-added', bytes: bytes.length)` from
`addBytes`. Install it before constructing each controller.

In `complete_example_test.dart`, pump `ContentRepositoryPage` directly, enter
text into its first `TextField`, tap `本地添加`, and assert a publication
`TextField` now contains `bafkrei-example-added`:

```dart
expect(
  find.byWidgetPredicate(
    (widget) => widget is TextField &&
        widget.controller?.text == 'bafkrei-example-added',
  ),
  findsOneWidget,
);
```

In `widget_test.dart`, pump `IpfsFeatureLabPage(autoStart: false)`, open the
`常用功能` tab, perform the same local add, and assert the publication field
changes from `documentedCid` to `bafkrei-example-added`.

- [ ] **Step 2: Run Example tests and verify RED where wiring is missing**

Run:

```sh
flutter test test/complete_example_test.dart test/widget_test.dart
```

Expected: both new tests FAIL because the add result is not handed to the
publication field.

- [ ] **Step 3: Implement Complete Example handoff**

Convert `ContentRepositoryPage` to a `StatefulWidget`, store
`String? _selectedCid`, pass `publicationSupported` and an `onAdded` callback to
`IpfsContentAddPanel`, and pass `_selectedCid` to
`IpfsCidPublicationPanel.initialCid`.

- [ ] **Step 4: Implement feature-lab handoff**

Add `String? _selectedCid` to `_IpfsFeatureLabPageState`. Pass `!kIsWeb` and an
`onAdded` callback to its add panel, then pass `_selectedCid ?? documentedCid`
to its publication panel.

- [ ] **Step 5: Run Example and package regressions**

Run:

```sh
flutter test test/complete_example_test.dart test/widget_test.dart test/example_operation_runner_test.dart
dart analyze lib test
```

from `example/`, then run:

```sh
flutter test test/ui_test.dart
dart analyze lib test
```

from `packages/ipfs_node_flutter/`.

Expected: all tests pass and both analyzers report `No issues found!`.

- [ ] **Step 6: Commit implementation**

```sh
git add example/lib/pages/content_repository_page.dart example/lib/main.dart \
  example/test/complete_example_test.dart example/test/widget_test.dart \
  packages/ipfs_node_flutter/lib/ui/ipfs_content_add_panel.dart \
  packages/ipfs_node_flutter/lib/ui/ipfs_cid_publication_panel.dart \
  packages/ipfs_node_flutter/test/ui_test.dart
git commit -m "feat: link publication workflow in IPFS example"
```
