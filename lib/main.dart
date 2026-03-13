import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database/app_database.dart';

/// Global database instance, provided via Riverpod.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase initialization is deferred — it requires URL and anonKey
  // which come from environment config. The app works fully offline
  // without Supabase (local Drift DB is the source of truth).
  //
  // To enable Supabase, call SupabaseService.instance.init() with
  // your project credentials before auth screens are shown.

  runApp(
    const ProviderScope(
      child: LineGuideApp(),
    ),
  );
}
