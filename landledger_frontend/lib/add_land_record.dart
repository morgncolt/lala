import 'package:flutter/material.dart';
import 'database_service.dart';

class AddLandRecordScreen extends StatefulWidget {
  @override
  _AddLandRecordScreenState createState() => _AddLandRecordScreenState();
}

class _AddLandRecordScreenState extends State<AddLandRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController longitudeController = TextEditingController();
  final TextEditingController latitudeController = TextEditingController();
  final TextEditingController sizeController = TextEditingController();
  final TextEditingController documentUrlController = TextEditingController();
  final TextEditingController mapsImageUrlController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Land Record")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(controller: firstNameController, decoration: const InputDecoration(labelText: "First Name")),
              TextFormField(controller: lastNameController, decoration: const InputDecoration(labelText: "Last Name")),
              TextFormField(controller: longitudeController, decoration: const InputDecoration(labelText: "Longitude")),
              TextFormField(controller: latitudeController, decoration: const InputDecoration(labelText: "Latitude")),
              TextFormField(controller: sizeController, decoration: const InputDecoration(labelText: "Size in Acres")),
              TextFormField(controller: documentUrlController, decoration: const InputDecoration(labelText: "Document URL")),
              TextFormField(controller: mapsImageUrlController, decoration: const InputDecoration(labelText: "Google Maps Image URL")),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  await _databaseService.addLandRecord(
                    firstName: firstNameController.text,
                    lastName: lastNameController.text,
                    longitude: double.parse(longitudeController.text),
                    latitude: double.parse(latitudeController.text),
                    size: double.parse(sizeController.text),
                    documentUrl: documentUrlController.text,
                    mapsImageUrl: mapsImageUrlController.text,
                  );
                  Navigator.pop(context);
                },
                child: const Text("Submit"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
