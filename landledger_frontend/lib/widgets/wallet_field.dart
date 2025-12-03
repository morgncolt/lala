import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_client.dart';

class WalletField extends StatefulWidget {
  final TextEditingController controller;
  const WalletField({super.key, required this.controller});

  @override
  State<WalletField> createState() => _WalletFieldState();
}

class _WalletFieldState extends State<WalletField> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Get current user info for the API call
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      fetchWalletLabel(user.uid, user.email ?? '').then((w) {
        widget.controller.text = w;
        setState(() => _loading = false);
      }).catchError((e) {
        setState(() { _loading = false; _error = e.toString(); });
      });
    } else {
      setState(() { _loading = false; _error = 'No user logged in'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    return TextField(
      controller: widget.controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: 'Wallet Address',
        helperText: 'Linked to your account',
        errorText: _error,
      ),
    );
  }
}