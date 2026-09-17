import 'package:bluez/bluez.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/src/universal_ble_linux/universal_ble_linux.dart';
import 'package:universal_ble/universal_ble.dart';

// The classifier only uses exception types, not D-Bus transport state.
class _Rejected implements BlueZAuthenticationRejectedException {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Canceled implements BlueZAuthenticationCanceledException {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Timeout implements BlueZAuthenticationTimeoutException {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Failed implements BlueZAuthenticationFailedException {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('BlueZ refusal categories follow the pairing contract', () {
    for (final error in [_Rejected(), _Canceled(), _Timeout()]) {
      expect(pairingStateFromBlueZError(error), PairingState.rejectedByUser);
    }
    expect(pairingStateFromBlueZError(_Failed()), PairingState.failed);
  });

  test('text mentioning a refusal cannot impersonate a BlueZ error', () {
    for (final name in [
      'AuthenticationRejected',
      'AuthenticationCanceled',
      'AuthenticationTimeout',
    ]) {
      expect(pairingStateFromBlueZError(Exception(name)), PairingState.failed);
    }
  });
}
