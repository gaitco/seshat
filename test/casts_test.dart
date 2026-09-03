import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:test/test.dart';

enum Status { draft, live }

void main() {
  group('parse helpers', () {
    test('bool', () {
      expect(parseBool(null), isNull);
      expect(parseBool(true), isTrue);
      expect(parseBool(1), isTrue);
      expect(parseBool(0), isFalse);
      expect(parseBool('t'), isTrue);
      expect(parseBool('false'), isFalse);
      expect(() => parseBool('maybe'), throwsFormatException);
    });
    test('int and double', () {
      expect(parseInt('42'), 42);
      expect(parseInt(4.9), 4);
      expect(parseDouble(3), 3.0);
      expect(parseDouble('1.5'), 1.5);
      expect(parseInt(null), isNull);
    });
    test('dateTime accepts DateTime, ISO text and epoch millis', () {
      final d = DateTime.utc(2026, 9, 2, 10, 30);
      expect(parseDateTime(d), d);
      expect(parseDateTime('2026-09-02T10:30:00.000Z'), d);
      expect(parseDateTime(d.millisecondsSinceEpoch), d);
      expect(parseDateTime(null), isNull);
      expect(() => parseDateTime('yesterday'), throwsFormatException);
    });
    test('enum by name', () {
      expect(parseEnum(Status.values, 'live'), Status.live);
      expect(parseEnum(Status.values, Status.draft), Status.draft);
      expect(parseEnum(Status.values, null), isNull);
      expect(() => parseEnum(Status.values, 'gone'), throwsFormatException);
    });
    test('json', () {
      expect(parseJson('{"a":[1,2]}'), {
        'a': [1, 2],
      });
      expect(parseJson({'a': 1}), {'a': 1});
      expect(parseJson(null), isNull);
    });
  });

  group('Cast objects', () {
    test('enumeration encodes to name and decodes back', () {
      final cast = Cast.enumeration(Status.values);
      expect(cast.encode!(Status.live), 'live');
      expect(cast.decode('live'), Status.live);
    });
    test('json encodes maps to strings', () {
      expect(Cast.json.encode!({'k': 1}), '{"k":1}');
      expect(Cast.json.encode!(null), isNull);
    });
    test('definition applies casts both ways', () {
      final def = ModelDefinition<Map<String, Object?>>(
        table: 't',
        fromMap: (m) => m,
        casts: {
          'ok': Cast.boolean,
          'at': Cast.dateTime,
          'st': Cast.enumeration(Status.values),
        },
      );
      final decoded = def.decodeAttributes({
        'ok': 1,
        'at': '2026-01-01T00:00:00.000Z',
        'st': 'draft',
        'x': 'raw',
      });
      expect(decoded, {
        'ok': true,
        'at': DateTime.utc(2026),
        'st': Status.draft,
        'x': 'raw',
      });
      expect(def.encodeAttributes({'st': Status.live, 'ok': true}), {
        'st': 'live',
        'ok': true,
      });
    });
  });
}
