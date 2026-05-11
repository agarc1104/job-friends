import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobfriends_mobile/app.dart';

void main() {
  group('JobFriends smoke shell', () {
    testWidgets('boots app with expected title', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.title, 'JobFriends Mobile');
    });

    testWidgets('renders initial shell state safely', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    });
  });
}
