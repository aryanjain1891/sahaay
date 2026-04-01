import 'package:flutter_test/flutter_test.dart';
import 'package:sahaay/services/sos_service.dart';

void main() {
  group('SosTriggerResult', () {
    // ── Success ────────────────────────────────────────────────────────────

    group('success', () {
      test('has ok = true and carries the SOS id', () {
        final result = SosTriggerResult.success('sos-abc-123');

        expect(result.ok, isTrue);
        expect(result.sosId, 'sos-abc-123');
        expect(result.errorMessage, isNull);
        expect(result.wasDebounced, isFalse);
        expect(result.notAuthenticated, isFalse);
      });

      test('different ids are preserved exactly', () {
        final r1 = SosTriggerResult.success('id-1');
        final r2 = SosTriggerResult.success('id-2');

        expect(r1.sosId, 'id-1');
        expect(r2.sosId, 'id-2');
        expect(r1.sosId, isNot(r2.sosId));
      });
    });

    // ── Debounced ──────────────────────────────────────────────────────────

    group('debounced', () {
      test('has ok = false and wasDebounced = true', () {
        const result = SosTriggerResult.debounced;

        expect(result.ok, isFalse);
        expect(result.wasDebounced, isTrue);
        expect(result.sosId, isNull);
        expect(result.errorMessage, isNull);
        expect(result.notAuthenticated, isFalse);
      });
    });

    // ── Not authenticated ──────────────────────────────────────────────────

    group('notAuthenticatedResult', () {
      test('has ok = false and notAuthenticated = true', () {
        const result = SosTriggerResult.notAuthenticatedResult;

        expect(result.ok, isFalse);
        expect(result.notAuthenticated, isTrue);
        expect(result.sosId, isNull);
        expect(result.errorMessage, isNull);
        expect(result.wasDebounced, isFalse);
      });
    });

    // ── Error ──────────────────────────────────────────────────────────────

    group('error', () {
      test('has ok = false and carries the error message', () {
        final result = SosTriggerResult.error('Cloud Function timed out');

        expect(result.ok, isFalse);
        expect(result.errorMessage, 'Cloud Function timed out');
        expect(result.sosId, isNull);
        expect(result.wasDebounced, isFalse);
        expect(result.notAuthenticated, isFalse);
      });

      test('preserves different error messages', () {
        final r1 = SosTriggerResult.error('Timeout');
        final r2 = SosTriggerResult.error('Network error');

        expect(r1.errorMessage, 'Timeout');
        expect(r2.errorMessage, 'Network error');
      });

      test('empty error message is allowed', () {
        final result = SosTriggerResult.error('');

        expect(result.ok, isFalse);
        expect(result.errorMessage, '');
      });
    });

    // ── Mutual exclusivity ─────────────────────────────────────────────────

    group('states are mutually exclusive', () {
      test('success has no error flags set', () {
        final result = SosTriggerResult.success('x');
        expect(result.ok, isTrue);
        expect(result.wasDebounced, isFalse);
        expect(result.notAuthenticated, isFalse);
        expect(result.errorMessage, isNull);
      });

      test('debounced is not confused with notAuthenticated', () {
        const result = SosTriggerResult.debounced;
        expect(result.wasDebounced, isTrue);
        expect(result.notAuthenticated, isFalse);
      });

      test('notAuthenticated is not confused with debounced', () {
        const result = SosTriggerResult.notAuthenticatedResult;
        expect(result.notAuthenticated, isTrue);
        expect(result.wasDebounced, isFalse);
      });

      test('error does not set debounced or notAuthenticated', () {
        final result = SosTriggerResult.error('fail');
        expect(result.wasDebounced, isFalse);
        expect(result.notAuthenticated, isFalse);
        expect(result.errorMessage, isNotNull);
      });
    });
  });
}
