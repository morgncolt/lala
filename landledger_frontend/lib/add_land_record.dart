import 'package:flutter/material.dart';
import 'database_service.dart';

class AddLandRecordScreen extends StatefulWidget {
  const AddLandRecordScreen({super.key});

  @override
  State<AddLandRecordScreen> createState() => _AddLandRecordScreenState();
}

class _AddLandRecordScreenState extends State<AddLandRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _documentUrlController = TextEditingController();
  final TextEditingController _mapsImageUrlController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _longitudeController.dispose();
    _latitudeController.dispose();
    _sizeController.dispose();
    _documentUrlController.dispose();
    _mapsImageUrlController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await _databaseService.addLandRecord(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        longitude: double.parse(_longitudeController.text.trim()),
        latitude: double.parse(_latitudeController.text.trim()),
        size: double.parse(_sizeController.text.trim()),
        documentUrl: _documentUrlController.text.trim(),
        mapsImageUrl: _mapsImageUrlController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true); // Return success
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving record: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Land Record")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: "First Name"),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: "Last Name"),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _longitudeController,
                decoration: const InputDecoration(labelText: "Longitude"),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid number';
                  return null;
                },
              ),
              TextFormField(
                controller: _latitudeController,
                decoration: const InputDecoration(labelText: "Latitude"),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid number';
                  return null;
                },
              ),
              TextFormField(
                controller: _sizeController,
                decoration: const InputDecoration(labelText: "Size in Acres"),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid number';
                  if (double.parse(value) <= 0) return 'Must be positive';
                  return null;
                },
              ),
              TextFormField(
                controller: _documentUrlController,
                decoration: const InputDecoration(labelText: "Document URL"),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _mapsImageUrlController,
                decoration: const InputDecoration(labelText: "Google Maps Image URL"),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitForm,
                child: _isSubmitting
                    ? const CircularProgressIndicator()
                    : const Text("Submit"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}