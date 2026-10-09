import 'package:flutter/foundation.dart';

class RedactingLogger {
  static String redact(String input) {
    if (input.isEmpty) return input;

    return input
        .replaceAll(
          RegExp(r'sk-[A-Za-z0-9_-]+', caseSensitive: false),
          '[redacted]',
        )
        .replaceAll(
          RegExp(r'gsk_[A-Za-z0-9_-]+', caseSensitive: false),
          '[redacted]',
        )
        .replaceAll(
          RegExp(r'AIza[0-9A-Za-z_-]+', caseSensitive: false),
          '[redacted]',
        )
        .replaceAll(
          RegExp(
            r'(email|e-mail|mail)\s*[:=]\s*[^\s,;]+',
            caseSensitive: false,
          ),
          'mail=[redacted]',
        )
        .replaceAll(
          RegExp(r'(phone|mobile)\s*[:=]\s*[^\s,;]+', caseSensitive: false),
          'phone=[redacted]',
        );
  }

  static void log(String message) {
    debugPrint(redact(message));
  }
}
