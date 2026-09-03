import 'dart:convert';

/// Converts one column between its database form and its Dart form.
///
/// Register casts on a [ModelDefinition] and `fromMap` receives Dart
/// values (`bool`, `DateTime`, enums, decoded JSON); `toMap` may return
/// those same Dart values and they are encoded on the way out.
///
/// ```dart
/// casts: {'active': Cast.boolean, 'created_at': Cast.dateTime,
///         'role': Cast.enumeration(Role.values), 'meta': Cast.json}
/// ```
class Cast {
  const Cast(this.decode, [this.encode]);

  /// Database value → Dart value.
  final Object? Function(Object? value) decode;

  /// Dart value → database value. `null` means "let the grammar decide".
  final Object? Function(Object? value)? encode;

  static const boolean = Cast(parseBool);
  static const integer = Cast(parseInt);
  static const double_ = Cast(parseDouble);
  static const string = Cast(parseString);
  static const dateTime = Cast(parseDateTime);
  static const json = Cast(parseJson, _encodeJson);

  /// Stores the enum's `name`.
  static Cast enumeration<E extends Enum>(List<E> values) =>
      Cast((v) => parseEnum(values, v), (v) => v is Enum ? v.name : v);

  static Object? _encodeJson(Object? v) => v == null ? null : jsonEncode(v);
}

/// Accepts `bool`, `0`/`1`, `'true'`/`'false'`, `'t'`/`'f'`.
bool? parseBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = value.toString().toLowerCase();
  if (s == 'true' || s == 't' || s == '1') return true;
  if (s == 'false' || s == 'f' || s == '0' || s == '') return false;
  throw FormatException('Cannot cast $value to bool');
}

int? parseInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

double? parseDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.parse(value.toString());
}

String? parseString(Object? value) => value?.toString();

/// Accepts [DateTime], ISO-8601 text, or milliseconds since the epoch.
DateTime? parseDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  return DateTime.parse(value.toString());
}

E? parseEnum<E extends Enum>(List<E> values, Object? value) {
  if (value == null) return null;
  if (value is E) return value;
  final name = value.toString();
  return values.firstWhere(
    (e) => e.name == name,
    orElse: () => throw FormatException("No enum value named '$name'"),
  );
}

/// Accepts a JSON string or an already-decoded `Map`/`List`.
Object? parseJson(Object? value) {
  if (value == null || value is Map || value is List) return value;
  return jsonDecode(value.toString());
}
