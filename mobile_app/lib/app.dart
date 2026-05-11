import 'package:flutter/material.dart';

import 'features/shell/home_shell.dart';
import 'theme/app_theme.dart';

class JobFriendsApp extends StatelessWidget {
  const JobFriendsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JobFriends Mobile',
      debugShowCheckedModeBanner: false,
      theme: buildJobFriendsTheme(),
      home: const HomeShell(),
    );
  }
}