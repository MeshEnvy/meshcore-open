import 'dart:async';

class MessageSegment {
  final int pageNum;
  final int totalPages;
  final String mid;
  final String content;

  MessageSegment({
    required this.pageNum,
    required this.totalPages,
    required this.mid,
    required this.content,
  });

  static MessageSegment? parse(String text) {
    final regex = RegExp(r'^\[(\d+)/(\d+)([a-z])\](.*)$', dotAll: true);
    final match = regex.firstMatch(text);
    if (match == null) return null;

    final pageNum = int.tryParse(match.group(1) ?? '');
    final totalPages = int.tryParse(match.group(2) ?? '');
    final mid = match.group(3) ?? '';
    final content = match.group(4) ?? '';

    if (pageNum == null || totalPages == null) return null;

    return MessageSegment(
      pageNum: pageNum,
      totalPages: totalPages,
      mid: mid,
      content: content,
    );
  }
}

class MessageAssembler {
  final void Function(String senderId, String text) onMessageAssembled;
  final void Function(String senderId, List<MessageSegment> segments)
  onMessageFailed;
  final Duration timeout;

  final Map<String, _AssemblySession> _sessions = {};

  MessageAssembler({
    required this.onMessageAssembled,
    required this.onMessageFailed,
    this.timeout = const Duration(seconds: 5),
  });

  void addSegment(String senderId, String text) {
    final segment = MessageSegment.parse(text);
    if (segment == null) {
      // Not a multi-part message, just pass it through?
      // Actually, MeshCoreConnector should handle non-multi-part messages itself.
      return;
    }

    final sessionKey = '${senderId}_${segment.mid}';
    var session = _sessions[sessionKey];

    if (session == null) {
      session = _AssemblySession(
        senderId: senderId,
        mid: segment.mid,
        totalPages: segment.totalPages,
        onTimeout: () => _handleTimeout(sessionKey),
        timeoutDuration: timeout,
      );
      _sessions[sessionKey] = session;
    }

    session.addSegment(segment);

    if (session.isComplete) {
      session.cancelTimeout();
      _sessions.remove(sessionKey);
      onMessageAssembled(senderId, session.assembledText);
    }
  }

  void _handleTimeout(String sessionKey) {
    final session = _sessions.remove(sessionKey);
    if (session != null) {
      final sortedSegments = session.segments.values.toList()
        ..sort((a, b) => a.pageNum.compareTo(b.pageNum));
      onMessageFailed(session.senderId, sortedSegments);
    }
  }
}

class _AssemblySession {
  final String senderId;
  final String mid;
  final int totalPages;
  final Map<int, MessageSegment> segments = {};
  final Duration timeoutDuration;
  final VoidCallback onTimeout;
  Timer? _timer;

  _AssemblySession({
    required this.senderId,
    required this.mid,
    required this.totalPages,
    required this.onTimeout,
    required this.timeoutDuration,
  }) {
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(timeoutDuration, onTimeout);
  }

  void addSegment(MessageSegment segment) {
    segments[segment.pageNum] = segment;
    // Reset timer on each new segment? The prompt says "if it sees a multipart message it will hold them for a few seconds to see if any new parts come in".
    // This implies we should probably reset the timer.
    _startTimer();
  }

  bool get isComplete => segments.length == totalPages;

  String get assembledText {
    final buffer = StringBuffer();
    for (var i = 1; i <= totalPages; i++) {
      buffer.write(segments[i]?.content ?? '');
    }
    return buffer.toString();
  }

  void cancelTimeout() {
    _timer?.cancel();
  }
}

typedef VoidCallback = void Function();
