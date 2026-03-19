// lib/services/current_user.dart

class CurrentUser {
  static final CurrentUser instance = CurrentUser._internal();
  CurrentUser._internal();

  String? id;
  String? username;
  String? firstname;
  String? lastname;
  String? color; 
  String? email; 
  String? contactNumber;
  bool? isGcashReady;
  String? status;
  String? avatarUrl;

  void setFromMap(Map<String, dynamic> data) {
    id = data['id'];
    username = data['username'];
    firstname = data['firstname'];
    lastname = data['lastname'];
    color = data['color'];
    email = data['email']; 
    contactNumber = data['contact_number'] as String?;
    isGcashReady = data['is_gcash_ready'] as bool? ?? false;
    status = data['status'] as String?;
    avatarUrl = data['avatar_url'] as String?;
  }

  void clear() {
    id = null;
    username = null;
    firstname = null;
    lastname = null;
    color = null;
    email = null;
    contactNumber = null;
    isGcashReady = null;
    status = null; 
    avatarUrl = null;
  }
}