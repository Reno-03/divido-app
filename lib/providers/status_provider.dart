import 'package:flutter/foundation.dart';

class StatusProvider extends ChangeNotifier {
  String? _status;

  String? get status => _status;

  void setStatus(String? newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void clear() {
    _status = null;
    notifyListeners();
  }
}