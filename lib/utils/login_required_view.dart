import 'package:flutter/material.dart';
import 'require_login.dart';

/// Shown in a tab when the visitor is a guest. Tapping the button opens your
/// existing login / sign-up screen via requireLogin(); after login AuthGate
/// rebuilds the app in logged-in mode.
class LoginRequiredView extends StatelessWidget {
  final String title;
  final String message;
  const LoginRequiredView({
    super.key,
    required this.title,
    this.message = 'Log in to see this page and manage your shop.',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.blue[900]),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => requireLogin(context),
                icon: const Icon(Icons.login),
                label: const Text('Log in or sign up'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[900],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}