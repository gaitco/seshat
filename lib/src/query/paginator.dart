/// One page of results plus the numbers a UI needs to draw pagination.
class Paginator<T> {
  Paginator({
    required this.data,
    required this.total,
    required this.perPage,
    required this.currentPage,
  }) : lastPage = total == 0 ? 1 : (total / perPage).ceil();

  final List<T> data;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;

  bool get hasMorePages => currentPage < lastPage;
  bool get onFirstPage => currentPage <= 1;
  int? get nextPage => hasMorePages ? currentPage + 1 : null;
  int? get previousPage => onFirstPage ? null : currentPage - 1;

  /// 1-based index of the first item on this page, `null` when empty.
  int? get from => data.isEmpty ? null : (currentPage - 1) * perPage + 1;
  int? get to => data.isEmpty ? null : from! + data.length - 1;

  /// Laravel-shaped JSON. Items are serialised with [item] (defaults to
  /// calling `toJson()`/`toMap()` when present).
  Map<String, Object?> toJson([Object? Function(T item)? item]) => {
    'data': [for (final d in data) item == null ? _serialize(d) : item(d)],
    'total': total,
    'per_page': perPage,
    'current_page': currentPage,
    'last_page': lastPage,
    'from': from,
    'to': to,
  };

  static Object? _serialize(Object? value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    }
    try {
      return (value as dynamic).toJson();
    } on NoSuchMethodError {
      return (value as dynamic).toMap();
    }
  }
}
