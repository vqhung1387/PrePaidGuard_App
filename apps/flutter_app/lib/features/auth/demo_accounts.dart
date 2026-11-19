class DemoAccounts {
  static const exampleEmail = 'demo@example.com';
  static const examplePassword = 'demo1234';

  final _passwords = <String, String>{exampleEmail: examplePassword};

  String? signIn(String email, String password) {
    if (_passwords[email] != password) {
      return 'Email hoặc mật khẩu demo chưa đúng.';
    }
    return null;
  }

  String? register(String email, String password) {
    if (_passwords.containsKey(email)) {
      return 'Email này đã có tài khoản demo. Hãy đăng nhập.';
    }
    _passwords[email] = password;
    return null;
  }
}
