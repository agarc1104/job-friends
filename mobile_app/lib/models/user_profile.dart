class UserProfile {
  const UserProfile({
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
  });

  final String email;
  final String firstName;
  final String lastName;
  final String phone;

  String get fullName => '$firstName $lastName'.trim();

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      email: (data['Email'] ?? '').toString(),
      firstName: (data['First_Name'] ?? '').toString(),
      lastName: (data['Last_Name'] ?? '').toString(),
      phone: (data['Phone'] ?? '').toString(),
    );
  }
}