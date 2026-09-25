import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Extremely lightweight, zero-dependency local HTTP streaming server.
///
/// Designed exclusively to serve external / security-scoped video files to WKWebView.
/// Strictly on-demand lifecycle:
/// - Spins up on 127.0.0.1 with an OS-allocated random port.
/// - Supports standard HTTP 206 (Partial Content / Range requests) for instant seeking and low memory.
/// - Completely shuts down and unbinds socket as soon as playback stops.
class LocalVideoServer {
  LocalVideoServer._();
  static final LocalVideoServer instance = LocalVideoServer._();

  HttpServer? _server;
  File? _activeFile;
  String? _activeUrl;
  String? _mimeType;

  /// Returns whether the server is currently actively listening.
  bool get isRunning => _server != null;

  /// Serves the specified [file] via local loopback HTTP stream.
  ///
  /// Reuses existing server instance if already bound; updates the active file.
  Future<String> serveFile(File file) async {
    if (_server != null && _activeFile?.path == file.path && _activeUrl != null) {
      return _activeUrl!;
    }

    _activeFile = file;
    _mimeType = _detectMimeType(file.path);

    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(
        _handleRequest,
        onError: (Object error) {
          debugPrint('[LocalVideoServer] Server error: $error');
        },
      );
    }

    final ext = p.extension(file.path);
    _activeUrl = 'http://127.0.0.1:${_server!.port}/video$ext';
    return _activeUrl!;
  }

  /// Stops the local server, closes all sockets, and releases resources immediately.
  Future<void> stop() async {
    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (_) {}
      _server = null;
    }
    _activeFile = null;
    _activeUrl = null;
    _mimeType = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      final file = _activeFile;
      if (file == null || !await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final totalLength = await file.length();
      final mime = _mimeType ?? 'video/mp4';

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, mime);
      response.headers.set('Cache-Control', 'no-cache');
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.headers.set('Access-Control-Allow-Headers', '*');

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      if (rangeHeader == null || !rangeHeader.startsWith('bytes=')) {
        // Full content request (200 OK)
        response.statusCode = HttpStatus.ok;
        response.headers.contentLength = totalLength;

        if (request.method == 'HEAD') {
          await response.close();
          return;
        }

        await response.addStream(file.openRead());
        await response.close();
        return;
      }

      // Range request (206 Partial Content)
      final match = RegExp(r'^bytes=(\d+)-(\d+)?$').firstMatch(rangeHeader.trim());
      if (match == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
        await response.close();
        return;
      }

      final start = int.parse(match.group(1)!);
      final end = match.group(2) != null ? int.parse(match.group(2)!) : totalLength - 1;

      if (start >= totalLength || end >= totalLength || start > end) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
        await response.close();
        return;
      }

      final chunkLength = end - start + 1;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalLength');
      response.headers.contentLength = chunkLength;

      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      // Stream the range using RandomAccessFile in 64KB chunks
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(start);
        int remaining = chunkLength;
        const bufferSize = 64 * 1024;

        while (remaining > 0) {
          final toRead = remaining > bufferSize ? bufferSize : remaining;
          final bytes = await raf.read(toRead);
          if (bytes.isEmpty) break;
          response.add(bytes);
          remaining -= bytes.length;
          await response.flush();
        }
      } finally {
        await raf.close();
      }

      await response.close();
    } catch (_) {
      // Client aborts (e.g. rapid seek / scrubbing) are normal and expected in video streaming.
      try {
        await response.close();
      } catch (_) {}
    }
  }

  static String _detectMimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.m4v':
        return 'video/x-m4v';
      case '.webm':
        return 'video/webm';
      case '.ogv':
        return 'video/ogg';
      case '.mkv':
        return 'video/x-matroska';
      case '.avi':
        return 'video/x-msvideo';
      default:
        return 'video/mp4';
    }
  }
}
