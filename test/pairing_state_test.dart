import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

/// Minimal platform used to drive [UniversalBlePlatform.updatePairingState].
final class _PairingPlatform extends UniversalBlePlatform {
  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  Future<bool> enableBluetooth() async => true;

  @override
  Future<bool> disableBluetooth() async => true;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {}

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => const [];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async => Uint8List(0);

  @override
  Future<Uint8List> readDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor, {
    Duration? timeout,
  }) async => Uint8List(0);

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {}

  @override
  Future<void> writeDescriptorValue(
    String deviceId,
    String service,
    String characteristic,
    String descriptor,
    Uint8List value,
  ) async {}

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => expectedMtu;

  @override
  Future<int> readRssi(String deviceId) async => 0;

  @override
  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  ) async {}

  @override
  Future<bool> isPaired(String deviceId) async => false;

  @override
  Future<bool> pair(String deviceId) async => false;

  @override
  Future<void> unpair(String deviceId) async {}

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      BleConnectionState.disconnected;

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async =>
      const [];
}

void main() {
  const deviceId = 'AA:BB:CC:DD:EE:FF';

  test('pairingStateStream reports a user refusal distinctly', () async {
    final platform = _PairingPlatform();
    final states = <PairingState>[];
    final sub = platform.pairingStateStream(deviceId).listen(states.add);

    platform.updatePairingState(deviceId, PairingState.pairing);
    platform.updatePairingState(deviceId, PairingState.rejectedByUser);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();

    expect(states, [PairingState.pairing, PairingState.rejectedByUser]);
  });

  test('a refusal is not conflated with a plain bonding failure', () async {
    final platform = _PairingPlatform();
    final states = <PairingState>[];
    final sub = platform.pairingStateStream(deviceId).listen(states.add);

    platform.updatePairingState(deviceId, PairingState.failed);
    platform.updatePairingState(deviceId, PairingState.rejectedByUser);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();

    expect(states, [PairingState.failed, PairingState.rejectedByUser]);
  });

  test('onPairingStateChange receives the typed outcome', () async {
    final platform = _PairingPlatform();
    PairingState? received;
    platform.onPairingStateChange = (_, state) => received = state;

    platform.updatePairingState(deviceId, PairingState.rejectedByUser);

    expect(received, PairingState.rejectedByUser);
  });

  test('a repeated refusal is reported for every attempt', () async {
    // Windows and Apple have no `pairing` progress event, so two refused
    // attempts in a row produce two identical states; deduping them would
    // leave the retried pair() without any outcome.
    final platform = _PairingPlatform();
    final states = <PairingState>[];
    final sub = platform.pairingStateStream(deviceId).listen(states.add);

    platform.updatePairingState(deviceId, PairingState.rejectedByUser);
    platform.updatePairingState(deviceId, PairingState.rejectedByUser);
    platform.updatePairingState(deviceId, PairingState.failed);
    platform.updatePairingState(deviceId, PairingState.failed);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();

    expect(states, [
      PairingState.rejectedByUser,
      PairingState.rejectedByUser,
      PairingState.failed,
      PairingState.failed,
    ]);
  });

  test('a steady bond is still reported only once', () async {
    final platform = _PairingPlatform();
    final states = <PairingState>[];
    final sub = platform.pairingStateStream(deviceId).listen(states.add);

    platform.updatePairingState(deviceId, PairingState.paired);
    platform.updatePairingState(deviceId, PairingState.paired);
    platform.updatePairingState(deviceId, PairingState.unpaired);
    platform.updatePairingState(deviceId, PairingState.unpaired);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();

    expect(states, [PairingState.paired, PairingState.unpaired]);
  });

  test('unknown Pigeon error indexes do not mask the original failure', () {
    for (final code in ['-1', '999999', 'not-a-number']) {
      expect(UniversalBle.pairingStateFromError(PlatformException(code: code)),
          isNull);
    }
    expect(
      UniversalBle.pairingStateFromError(PlatformException(
        code: UniversalBleErrorCode.insufficientAuthentication.index.toString(),
      )),
      PairingState.failed,
    );
  });

  group('Apple pairing outcome is derived from the operation error', () {
    // Apple exposes no bonding API: pairing happens implicitly when an
    // encrypted characteristic is touched, so the only signal about a
    // refused pairing dialog is the error of that read/write.
    PairingState? stateFor(UniversalBleErrorCode code) =>
        UniversalBle.pairingStateFromError(
          UniversalBleException(code: code, message: code.name),
        );

    test('ambiguous authentication errors are not user refusals', () {
      for (final code in [
        UniversalBleErrorCode.authenticationFailure,
        UniversalBleErrorCode.insufficientAuthentication,
        UniversalBleErrorCode.insufficientKeySize,
        UniversalBleErrorCode.pairingTimeout,
      ]) {
        expect(stateFor(code), PairingState.failed, reason: code.name);
      }
      expect(stateFor(UniversalBleErrorCode.pairingCancelled),
          PairingState.rejectedByUser);
    });

    test('a peripheral that cannot bond is a plain failure', () {
      expect(
        stateFor(UniversalBleErrorCode.pairingFailed),
        PairingState.failed,
      );
      expect(
        stateFor(UniversalBleErrorCode.notPairable),
        PairingState.failed,
      );
    });

    test('unrelated errors report no pairing outcome at all', () {
      expect(stateFor(UniversalBleErrorCode.deviceDisconnected), isNull);
      expect(stateFor(UniversalBleErrorCode.connectionTimeout), isNull);
    });
  });
}
