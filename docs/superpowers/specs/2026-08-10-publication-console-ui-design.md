# IPFS publication console UI

## Purpose

Make the distinction between locally stored content and publicly retrievable
content explicit in the example application.

## Native console

The feature tab contains four cards:

1. Network diagnostics: DHT routing readiness, relay reservation, direct
   public reachability, final `networkReady` state, and actionable reason when
   publication is unavailable.
2. Content operations: separate "add locally" and "add and publish" actions.
   The latter uses `addAndProvide` and shows typed failures without claiming a
   public CID was created.
3. CID state: local presence, pin state, last successful publication, most
   recent error, retry publication, and provider lookup.
4. Repository and external verification: repository path and local counts;
   a native-only, opt-in Kubo verification action reports provider lookup and
   block retrieval outcomes.

## Web console

Web retains local IndexedDB add, pin, get, and peer reads. Publication and
Kubo verification controls are disabled with an explanation because the
browser adapter does not advertise `publicPublication`.

## Validation

Widget tests cover button enablement, local-add success, unsupported Web
publication messaging, and network diagnostics rendering. Native integration
tests continue to cover the actual DHT/relay and Kubo behavior.
