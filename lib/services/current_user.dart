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

  void setFromMap(Map<String, dynamic> data) {
    id = data['id'];
    username = data['username'];
    firstname = data['firstname'];
    lastname = data['lastname'];
    color = data['color'];
    email = data['email']; 
    contactNumber = data['contact_number'] as String?;
  }

  void clear() {
    id = null;
    username = null;
    firstname = null;
    lastname = null;
    color = null;
    email = null;
    contactNumber = null;
  }
}