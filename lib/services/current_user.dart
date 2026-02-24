// lib/services/current_user.dart

class CurrentUser {
  static final CurrentUser instance = CurrentUser._internal();
  CurrentUser._internal();

  String? id;
  String? username;
  String? firstname;
  String? lastname;
  String? color; // 👈 add this

  void setFromMap(Map<String, dynamic> data) {
    id = data['id'];
    username = data['username'];
    firstname = data['firstname'];
    lastname = data['lastname'];
    color = data['color']; // 👈 add this
  }

  void clear() {
    id = null;
    username = null;
    firstname = null;
    lastname = null;
    color = null; // 👈 add this
  }
}