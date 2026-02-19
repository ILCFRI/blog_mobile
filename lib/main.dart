import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://omywzwztzryfkgmdixbu.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9teXd6d3p0enJ5ZmtnbWRpeGJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3Mjk5NjMsImV4cCI6MjA4NDMwNTk2M30.rea0jI7AoIlKvkbZ6ABQepZAjpquq-lKxuAS9lRXPSw',
  );

  runApp( const MyApp());
}
