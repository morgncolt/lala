import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showAccountSuggestions = true;
  bool _likeCountsVisible = true;
  final bool _secureLoginEnabled = true;
  bool _communityNotifications = true;
  bool _transactionAlerts = true;

  void _openHelpDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Settings'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Profile Section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage('https://via.placeholder.com/150'),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Morgan Cie',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Land Owner since 2022',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        ),
                        child: const Text('Edit Profile'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(),

            // Account Settings
            _buildSectionHeader('Account Settings'),
            _buildSettingsTile(
              icon: Icons.security,
              title: 'Login & Security',
              subtitle: 'Password, 2FA, and login methods',
              onTap: () => _openHelpDialog(
                'Login & Security',
                'Manage your account security settings:\n\n• Change password\n• Set up two-factor authentication\n• Manage trusted devices\n• View login activity',
              ),
            ),
            _buildSettingsTile(
              icon: Icons.privacy_tip,
              title: 'Privacy',
              subtitle: 'Manage your data and visibility',
              onTap: () => _openHelpDialog(
                'Privacy Settings',
                'Control what information is visible to others:\n\n• Property visibility\n• Contact information\n• Transaction history\n• Community participation',
              ),
            ),
            _buildSettingsTile(
              icon: Icons.ads_click,
              title: 'Ad Preferences',
              subtitle: 'Manage personalized ads',
              onTap: () => _openHelpDialog(
                'Ad Preferences',
                'Customize your advertising experience:\n\n• Interest-based ads\n• Partner data\n• Ad topics',
              ),
            ),

            // Content Preferences
            _buildSectionHeader('Content Preferences'),
            _buildSwitchTile(
              icon: Icons.visibility,
              title: 'Show like counts',
              subtitle: 'Display likes on properties and posts',
              value: _likeCountsVisible,
              onChanged: (value) => setState(() => _likeCountsVisible = value),
            ),
            _buildSwitchTile(
              icon: Icons.group,
              title: 'Show account suggestions',
              subtitle: 'Suggest similar accounts to follow',
              value: _showAccountSuggestions,
              onChanged: (value) => setState(() => _showAccountSuggestions = value),
            ),
            _buildSettingsTile(
              icon: Icons.filter_alt,
              title: 'Content filters',
              subtitle: 'Manage what you see in your feed',
              onTap: () => _openHelpDialog(
                'Content Filters',
                'Customize your feed experience:\n\n• Property types\n• Location preferences\n• Community content\n• Sensitive content filters',
              ),
            ),

            // Notifications
            _buildSectionHeader('Notifications'),
            _buildSwitchTile(
              icon: Icons.notifications,
              title: 'Community updates',
              subtitle: 'CIF proposals and community news',
              value: _communityNotifications,
              onChanged: (value) => setState(() => _communityNotifications = value),
            ),
            _buildSwitchTile(
              icon: Icons.payment,
              title: 'Transaction alerts',
              subtitle: 'Property transfers and payments',
              value: _transactionAlerts,
              onChanged: (value) => setState(() => _transactionAlerts = value),
            ),
            _buildSettingsTile(
              icon: Icons.email,
              title: 'Email preferences',
              subtitle: 'Manage email notifications',
              onTap: () => _openHelpDialog(
                'Email Preferences',
                'Control which emails you receive:\n\n• Weekly digests\n• Security alerts\n• Promotional offers\n• Community updates',
              ),
            ),

            // Support
            _buildSectionHeader('Support'),
            _buildSettingsTile(
              icon: Icons.help,
              title: 'Help Center',
              subtitle: 'FAQs and support articles',
              onTap: () => _openHelpDialog(
                'Help Center',
                'Access our comprehensive help resources:\n\n• Getting started guide\n• Property registration help\n• CIF documentation\n• Blockchain verification',
              ),
            ),
            _buildSettingsTile(
              icon: Icons.contact_support,
              title: 'Contact Support',
              subtitle: 'Get in touch with our team',
              onTap: () => launchUrl(Uri.parse('mailto:support@landledger.africa')),
            ),
            _buildSettingsTile(
              icon: Icons.info,
              title: 'About LandLedger',
              subtitle: 'Version 1.0.0 • Terms & Privacy',
              onTap: () => _openHelpDialog(
                'About LandLedger',
                'LandLedger Africa v1.0.0\n\nUsing Hyperledger blockchain technology to secure property rights across Africa.\n\n© 2023 LandLedger Africa\n\nTerms of Service • Privacy Policy',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage: NetworkImage('https://via.placeholder.com/150'),
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('Change Profile Photo'),
            ),
            const SizedBox(height: 20),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'Morgan Cie',
              ),
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'att4eva',
                prefixText: '@',
              ),
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Website',
                hintText: 'https://www.att4eva.com',
              ),
            ),
            const SizedBox(height: 16),
            const TextField(
              maxLines: 3,
              maxLength: 150,
              decoration: InputDecoration(
                labelText: 'Bio',
                hintText: 'Just renewed my 2024 Costco membership...',
                counterText: '51/150',
              ),
            ),
            const SizedBox(height: 16),
            const ListTile(
              title: Text('Gender'),
              subtitle: Text('Prefer not to say'),
              trailing: Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Show account suggestions'),
              subtitle: const Text('Suggest your profile to others'),
              value: true,
              onChanged: (value) {},
            ),
            const SizedBox(height: 24),
            const Text(
              'Certain profile info, like your name and bio, is visible to everyone.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}