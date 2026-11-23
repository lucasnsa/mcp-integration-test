import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _notifications = false;
  String? _saved;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile form')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            key: const ValueKey('profile-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Name is required'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('profile-email'),
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (value) =>
                RegExp(
                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                ).hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter a valid email',
          ),
          SwitchListTile(
            key: const ValueKey('notifications'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Email notifications'),
            value: _notifications,
            onChanged: (value) => setState(() => _notifications = value),
          ),
          FilledButton(
            key: const ValueKey('save-profile'),
            onPressed: () {
              if (_form.currentState!.validate()) {
                FocusScope.of(context).unfocus();
                setState(
                  () => _saved =
                      'Saved ${_name.text.trim()} (${_email.text.trim()}) — notifications ${_notifications ? 'on' : 'off'}',
                );
              }
            },
            child: const Text('Save profile'),
          ),
          if (_saved != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_saved!, key: const ValueKey('profile-result')),
            ),
        ],
      ),
    ),
  );
}
