// mock_ethereum_service.dart
import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';

class MockEthereumService with ChangeNotifier {
  bool _isInitialized = true; // Always "initialized" for mock
  List<Map<String, dynamic>> _mockProjects = [];

  bool get isInitialized => _isInitialized;

  // Simulate blockchain delay
  Future<void> _simulateBlockchainDelay() async {
    await Future.delayed(const Duration(seconds: 1));
  }

  // Mock contract creation
  Future<String> createContract(
    bool isPublic,
    String description,
    EtherAmount amount, {
    String? linkedTag,
  }) async {
    await _simulateBlockchainDelay();
    
    final newProject = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'title': description.split('\n').first,
      'description': description,
      'votes': 0,
      'funded': 0,
      'goal': amount.getInEther.toInt() * 1000, // Convert to CFA
      'image': isPublic ? '🏗️' : '🔒',
      'status': isPublic ? 'Voting' : 'Pending',
    };

    _mockProjects.add(newProject);
    notifyListeners();

    return "0xmock_tx_hash_${newProject['id']}";
  }

  // Mock voting
  Future<String> vote(int projectId) async {
    await _simulateBlockchainDelay();
    
    final project = _mockProjects.firstWhere(
      (p) => p['id'] == projectId,
      orElse: () => throw Exception("Project not found"),
    );

    project['votes'] += 1;
    notifyListeners();

    return "0xmock_vote_tx_${DateTime.now().millisecondsSinceEpoch}";
  }

  // Get mock projects (replace with your actual data structure)
  List<Map<String, dynamic>> getProjects(bool isPublic) {
    return _mockProjects.where((p) => p['status'] == (isPublic ? 'Voting' : 'Pending')).toList();
  }
}