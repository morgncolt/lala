import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart' show rootBundle;


class EthereumService with ChangeNotifier {
  late Web3Client _client;
  late DeployedContract _cifContract;
  late ContractFunction _createContract;
  late ContractFunction _vote;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      final sepoliaRpc = dotenv.env['SEPOLIA_RPC_URL'];
      if (sepoliaRpc == null || sepoliaRpc.isEmpty) {
        throw Exception('SEPOLIA_RPC_URL is not set in .env file');
      }

      debugPrint('Initializing Web3Client with RPC: $sepoliaRpc');
      _client = Web3Client(sepoliaRpc, Client());
      
      await _initContract();
      _isInitialized = true;
      notifyListeners();
      debugPrint('✅ EthereumService initialized successfully');
    } catch (e) {
      debugPrint('❌ EthereumService initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _initContract() async {
    try {
      final abi = await rootBundle.loadString('assets/contract_abi.json');
      final contractAddress = dotenv.env['CONTRACT_ADDRESS'];

       if (contractAddress == null || contractAddress.isEmpty) {
        throw Exception('CONTRACT_ADDRESS is not set in .env file');
      }

      debugPrint('Initializing contract at address: $contractAddress');
      _cifContract = DeployedContract(
        ContractAbi.fromJson(abi, 'CIFContract'),
        EthereumAddress.fromHex(contractAddress),
      );

      _createContract = _cifContract.function('createContract');
      _vote = _cifContract.function('vote');

      debugPrint('✅ Contract initialized: ${_cifContract.address.hex}');
    } catch (e) {
      debugPrint('❌ Failed to initialize contract: $e');
      rethrow;
    }
    

 
    _createContract = _cifContract.function('createContract');
    _vote = _cifContract.function('vote');
}


  Future<String> createContract(
    bool isPublic,
    String description,
    EtherAmount amount, {
    String? linkedTag,
  }) async {
    if (!_isInitialized) {
      throw Exception('EthereumService not initialized');
    }

    final credentials = await _client.credentialsFromPrivateKey(
      dotenv.env['PRIVATE_KEY']!,
    );

    if (linkedTag != null) {
      debugPrint('🔗 Linked property tag: $linkedTag');
    }

    final tx = Transaction.callContract(
      contract: _cifContract,
      function: _createContract,
      parameters: [
        isPublic, 
        description, // Added description parameter
        amount.getInWei,
        linkedTag ?? '', // Handle null linkedTag
      ],
      maxGas: 100000, // Added gas limit
    );

    final txHash = await _client.sendTransaction(credentials, tx);
    return txHash;
  }

  Future<String> vote(int contractId) async {
    if (!_isInitialized) {
      throw Exception('EthereumService not initialized');
    }

    final credentials = await _client.credentialsFromPrivateKey(
      dotenv.env['PRIVATE_KEY']!,
    );

    final tx = Transaction.callContract(
      contract: _cifContract,
      function: _vote,
      parameters: [BigInt.from(contractId)],
      maxGas: 100000, // Added gas limit
    );

    final txHash = await _client.sendTransaction(credentials, tx);
    return txHash;
  }

  // Add a dispose method to clean up resources
  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }
}