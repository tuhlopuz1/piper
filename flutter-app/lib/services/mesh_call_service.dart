// Mesh call utilities — re-exports CallService which contains attachMeshProxy
// and detachMeshProxy. Methods live on CallService directly because Dart
// library-privacy prevents subclassing across files.
export 'call_service.dart' show CallService;
