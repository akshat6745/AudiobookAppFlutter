import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';

class BackendNotifier extends StateNotifier<BackendChoice> {
  BackendNotifier() : super(currentBackend);

  Future<void> select(BackendChoice choice) async {
    if (choice == state) return;
    await setBackend(choice);
    state = choice;
  }
}

final backendProvider =
    StateNotifierProvider<BackendNotifier, BackendChoice>(
  (_) => BackendNotifier(),
);
