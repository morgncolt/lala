import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() async {
    user = _auth.currentUser;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("LandLedger Africa")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("LandLedger Africa")),
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (context) => LoginScreen())
            ),
            child: const Text("Log In Again"),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Welcome, ${user!.displayName ?? "User"}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _databaseService.getUserLandRecords(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("No land records found."),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => _showAddLandRecordDialog(),
                    child: const Text("Add Land Record"),
                  ),
                ],
              ),
            );
          }

          print("Land Records Found: ${snapshot.data!.docs.length}");

          var landRecords = snapshot.data!.docs;

          return ListView.builder(
            itemCount: landRecords.length,
            itemBuilder: (context, index) {
              var record = landRecords[index];
              var data = record.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  leading: GestureDetector(
                    onTap: () async {
                      final url = Uri.parse(
                          "https://www.google.com/maps/search/?api=1&query=${data["latitude"]},${data["longitude"]}");
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Image.network(
                      data["mapsImageUrl"] ?? "",
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported),
                    ),
                  ),
                  title: Text("${data["firstName"] ?? ""} ${data["lastName"] ?? ""}"),
                  subtitle: Text("Location: ${data["longitude"]}, ${data["latitude"]}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      _databaseService.deleteLandRecord(record.id);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddLandRecordDialog(),
        backgroundColor: const Color(0xFF00C896),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddLandRecordDialog() {
    TextEditingController latitudeController = TextEditingController();
    TextEditingController longitudeController = TextEditingController();
    TextEditingController sizeController = TextEditingController();
    TextEditingController documentUrlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Land Record"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: latitudeController, decoration: const InputDecoration(labelText: "Latitude"), keyboardType: TextInputType.number),
                TextField(controller: longitudeController, decoration: const InputDecoration(labelText: "Longitude"), keyboardType: TextInputType.number),
                TextField(controller: sizeController, decoration: const InputDecoration(labelText: "Size (acres)"), keyboardType: TextInputType.number),
                TextField(controller: documentUrlController, decoration: const InputDecoration(labelText: "Document URL")),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                double latitude = double.tryParse(latitudeController.text.trim()) ?? 0.0;
                double longitude = double.tryParse(longitudeController.text.trim()) ?? 0.0;
                double size = double.tryParse(sizeController.text.trim()) ?? 0.0;
                String documentUrl = documentUrlController.text.trim();

                if (latitude == 0.0 || longitude == 0.0 || size == 0.0 || documentUrl.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter all fields correctly!")),
                  );
                  return;
                }

                await _databaseService.addLandRecord(latitude, longitude, size, documentUrl);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Land Record Added Successfully!")),
                );

                Navigator.pop(context);
                setState(() {}); // Refresh the screen
              },
              child: const Text("Add Land Record"),
            ),
          ],
        );
      },
    );
  }
}
