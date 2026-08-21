import 'package:nsd/nsd.dart' as nsd;

class DeviceDiscoveryService {
  static const String serviceType = '_ecocube._tcp';

  nsd.Discovery? _discovery;

  Future<void> startDiscovery({
    required void Function(nsd.Service service) onDeviceFound,
  }) async {
    // Stop any previous discovery first.
    await stopDiscovery();

    // Start mDNS discovery.
    _discovery = await nsd.startDiscovery(
      serviceType,
      ipLookupType: nsd.IpLookupType.any,
    );

    // Listen for devices appearing/disappearing.
    _discovery!.addServiceListener(
      (service, status) {
        if (status == nsd.ServiceStatus.found) {
          onDeviceFound(service);
        }
      },
    );
  }

  Future<void> stopDiscovery() async {
    final discovery = _discovery;

    if (discovery != null) {
      await nsd.stopDiscovery(discovery);
      _discovery = null;
    }
  }

  Future<void> dispose() async {
    await stopDiscovery();
  }
}