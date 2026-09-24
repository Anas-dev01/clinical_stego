import 'package:flutter/material.dart';
import '../logic/auth_service.dart';
import '../main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  String _selectedHonorific = "Dr.";

  bool _isLogin = true;

  // Password Policy States
  bool _hasUpper = false;
  bool _hasLower = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;
  bool _hasMinLength = false;
  bool _isPasswordStrong = false;

  void _checkPasswordStrength(String value) {
    setState(() {
      _hasUpper = value.contains(RegExp(r'[A-Z]'));
      _hasLower = value.contains(RegExp(r'[a-z]'));
      _hasNumber = value.contains(RegExp(r'[0-9]'));
      _hasSpecial = value.contains(RegExp(r'[!@#\$&*~]'));
      _hasMinLength = value.length >= 8;
      _isPasswordStrong =
          _hasUpper && _hasLower && _hasNumber && _hasSpecial && _hasMinLength;
    });
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.teal),
            const SizedBox(height: 20),
            Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _handleAuth() async {
    String u = _userController.text.trim();
    String p = _passController.text.trim();
    if (u.isEmpty || p.isEmpty) return;

    if (_isLogin) {
      _showLoadingDialog("Authenticating Credentials...");
      await Future.delayed(const Duration(seconds: 4));

      final userData = await AuthService.login(u, p);

      if (!mounted) return;
      Navigator.pop(context);

      if (userData != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Dashboard(userData: userData)),
        );
      } else {
        _showStatus("Invalid Access Credentials", isError: true);
      }
    } else {
      if (!_isPasswordStrong) {
        _showStatus("Password policy not met", isError: true);
        return;
      }

      _showLoadingDialog("Creating Profile...");
      await Future.delayed(const Duration(seconds: 4));

      await AuthService.register(
        u,
        p,
        _firstNameController.text,
        _lastNameController.text,
        _selectedHonorific,
      );

      if (!mounted) return;
      Navigator.pop(context);

      setState(() => _isLogin = true);
      _showStatus("Account Created Successfully", isError: false);
    }
  }

  void _showStatus(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 30.0),
          child: Column(
            children: [
              const Icon(Icons.shield_moon, size: 70, color: Colors.teal),
              const SizedBox(height: 10),
              Text(
                _isLogin ? "CLINICAL STAFF LOGIN" : "STAFF REGISTRATION",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 30),

              if (!_isLogin) ...[
                // ARRANGEMENT FIX: Proper spacing for Honorific and Name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedHonorific,
                        decoration: const InputDecoration(
                          labelText: "Honorific",
                        ),
                        items: ["Dr.", "Prof.", "Nurse", "Consultant"]
                            .map(
                              (h) => DropdownMenuItem(
                                value: h,
                                child: Text(
                                  h,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedHonorific = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: TextField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(
                          labelText: "First Name",
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(labelText: "Last Name"),
                ),
                const SizedBox(height: 15),
              ],

              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: "Username",
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              TextField(
                controller: _passController,
                obscureText: true,
                onChanged: _checkPasswordStrength,
                decoration: const InputDecoration(
                  labelText: "Password",
                  prefixIcon: Icon(Icons.lock),
                ),
              ),

              if (!_isLogin) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      // RESTORED: All 4 specific policy conditions
                      _buildRequirement("Minimum 8 characters", _hasMinLength),
                      _buildRequirement(
                        "Uppercase & Lowercase letters",
                        _hasUpper && _hasLower,
                      ),
                      _buildRequirement(
                        "At least one numeric digit (0-9)",
                        _hasNumber,
                      ),
                      _hasSpecial
                          ? _buildRequirement(
                              "Special character detected",
                              true,
                            )
                          : _buildRequirement(
                              "Special character (!@#\$&*)",
                              false,
                            ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  backgroundColor: Colors.teal.shade800,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _handleAuth,
                child: Text(
                  _isLogin ? "LOGIN" : "CREATE ACCOUNT",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _userController.clear();
                    _passController.clear();
                  });
                },
                child: Text(
                  _isLogin ? "New Staff? Create Account" : "Back to Login",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequirement(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isMet ? Colors.green : Colors.grey,
            size: 14,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: isMet ? Colors.green : Colors.grey,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
