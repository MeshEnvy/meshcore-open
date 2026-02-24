import 'dart:convert';

class MessageSplitter {
  static String _currentMid = 'a';

  static String _nextMid() {
    final mid = _currentMid;
    final charCode = _currentMid.codeUnitAt(0);
    if (charCode >= 122) {
      // 'z'
      _currentMid = 'a';
    } else {
      _currentMid = String.fromCharCode(charCode + 1);
    }
    return mid;
  }

  /// Splits a message into chunks that fit within [maxBytes].
  /// Each chunk is prefixed with [<pageNum>/<totalPages><mid>].
  static List<String> split(String text, int maxBytes) {
    if (utf8.encode(text).length <= maxBytes) {
      return [text];
    }

    final mid = _nextMid();
    final chunks = <String>[];
    final bytes = utf8.encode(text);

    // We need to estimate prefix overhead.
    // Format: [n/Mmid] where n and M can be 1-3 digits usually.
    // Let's assume a safe overhead of 10-15 bytes per prefix.
    const estimatedPrefixOverhead = 15;
    final effectiveMaxBytes = maxBytes - estimatedPrefixOverhead;

    if (effectiveMaxBytes <= 0) {
      // This shouldn't happen with reasonable maxBytes, but safety first.
      return [text];
    }

    var start = 0;
    while (start < bytes.length) {
      var end = start + effectiveMaxBytes;
      if (end > bytes.length) {
        end = bytes.length;
      } else {
        // Ensure we don't split in the middle of a multi-byte UTF-8 character
        while (end > start && (bytes[end] & 0xC0) == 0x80) {
          end--;
        }
      }

      chunks.add(utf8.decode(bytes.sublist(start, end)));
      start = end;
    }

    final totalPages = chunks.length;
    final prefixedChunks = <String>[];
    for (var i = 0; i < totalPages; i++) {
      prefixedChunks.add('[${i + 1}/$totalPages$mid]${chunks[i]}');
    }

    return prefixedChunks;
  }
}
