import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_sniffer.dart';

final debugLogProvider = NotifierProvider<DebugLog, List<SniffedRequest>>(DebugLog.new);

/// In-memory list of Keka API calls seen in the WebView (debug builds only).
class DebugLog extends Notifier<List<SniffedRequest>> {
  static const _max = 200;

  @override
  List<SniffedRequest> build() => const [];

  void add(SniffedRequest request) {
    final next = [request, ...state];
    state = next.length > _max ? next.sublist(0, _max) : next;
  }

  void clear() => state = const [];
}
