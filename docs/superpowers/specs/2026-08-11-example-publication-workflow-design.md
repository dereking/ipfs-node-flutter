# Example Publication Workflow Integration Design

## Goal

Make the already implemented durable provider-publication APIs usable as one
continuous workflow in both Flutter Example entry points. Adding content must
automatically select its CID for strict publication, queued publication, status
inspection, queue inspection, and provider lookup.

This work does not add remote availability verification, remote pinning, or any
new IPFS network semantics.

## Shared UI contract

`IpfsContentAddPanel` will accept:

- `publicationSupported`, defaulting to `true`, to disable strict publication
  on backends such as web while retaining local add.
- `onAdded`, an optional callback invoked with the durable `IpfsAddResult`.

The callback runs after a local add, after a successful `addAndProvide`, and
after an `IpfsPublicationException`, because that exception proves the content
was stored and carries its durable CID. Other failures do not invoke it.

When publication is unsupported, the panel disables the publish action and
shows a concise explanation. It does not call the backend publication API.

## CID handoff

The Example stores the most recently added durable CID in page state and passes
it to `IpfsCidPublicationPanel`. The publication panel updates its text field
when a new `initialCid` arrives, allowing the user to immediately:

- perform strict provider publication;
- enqueue durable background publication;
- inspect confirmation, write, attempt, error, and retry metadata;
- inspect the full durable queue; and
- query DHT providers.

The four-page `CompleteExamplePage` and the existing feature-test entry point
both use this handoff. Existing manually entered CIDs remain supported.

## Error and platform behaviour

- Strict publication failure keeps and displays the CID, reports the error, and
  hands the CID to the publication panel.
- Local storage failure displays the error and does not change the selected CID.
- Web exposes local add/read/pin but disables publication UI and explains that
  provider publication is unsupported.
- A queued or failed publication remains inspectable through the existing
  persisted status APIs.

## Testing

Widget tests will first demonstrate the missing behaviour, then cover:

1. local add invokes `onAdded` and hands the CID to the publication panel;
2. strict publication failure still hands off the durable CID;
3. unsupported publication disables the publish action without invoking it;
4. a changed `initialCid` updates `IpfsCidPublicationPanel`;
5. both Example entry points expose the linked workflow.

Existing SDK, native, web, and Example tests remain unchanged in meaning and
must continue to pass.
