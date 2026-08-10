import 'platform_registration_io.dart'
    if (dart.library.js_interop) 'platform_registration_web.dart'
    as registration;

/// Registers the backend for the current platform.
///
/// The federated plugin registrant normally installs the backend before
/// `main` runs; this is an idempotent safety net that guarantees a backend is
/// always installed even if the generated plugin registrant is stale.
void registerIpfsNodePlatform() => registration.register();
