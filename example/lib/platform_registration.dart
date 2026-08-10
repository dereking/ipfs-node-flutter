import 'platform_registration_io.dart'
    if (dart.library.js_interop) 'platform_registration_web.dart'
    as registration;

/// Registers the backend for the current platform before the app starts.
void registerIpfsNodePlatform() => registration.register();
