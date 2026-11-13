import 'package:flutter_test/flutter_test.dart';

import 'package:jobfriends_mobile/data/jobfriends_repository.dart';

void main() {
  test('repository can be instantiated', () {
    const repository = JobFriendsRepository();

    expect(repository, isA<JobFriendsRepository>());
  });
}
