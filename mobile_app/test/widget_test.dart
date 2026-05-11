import 'package:flutter_test/flutter_test.dart';

import 'package:jobfriends_mobile/data/jobfriends_repository.dart';

void main() {
  test('hashes passwords with sha256 compatibility', () {
    const repository = JobFriendsRepository();

    expect(
      repository.hashPassword('hola123'),
      'b460b1982188f11d175f60ed670027e1afdd16558919fe47023ecd38329e0b7f',
    );
  });
}
