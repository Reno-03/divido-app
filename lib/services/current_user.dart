// lib/services/current_user.dart

class CurrentUser {
  static final CurrentUser instance = CurrentUser._internal();
  CurrentUser._internal();

  String? id;
  String? username;
  String? firstname;
  String? lastname;

  void setFromMap(Map<String, dynamic> data) {
    id = data['id'];
    username = data['username'];
    firstname = data['firstname'];
    lastname = data['lastname'];
  }

  void clear() {
    id = null;
    username = null;
    firstname = null;
    lastname = null;
  }
}