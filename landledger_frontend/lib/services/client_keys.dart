// lib/services/client_keys.dart
// TODO: Fix cryptography package API usage
// This file contains cryptographic key management utilities
// Currently disabled due to API compatibility issues

// import 'dart:convert';
// import 'package:cryptography/cryptography.dart' as crypto;
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// class ClientKeys {
//   static const _k = FlutterSecureStorage();
//   static const _privKey = 'fabric-p256-private';
//   static const _pubKey = 'fabric-p256-public';

//   // TODO: Fix cryptography API usage
//   // static final algorithm = crypto.Ecdsa.p256(crypto.Sha256());

//   // static Future<crypto.SimpleKeyPair> getOrCreate() async {
//   //   final savedPriv = await _k.read(key: _privKey);
//   //   final savedPub = await _k.read(key: _pubKey);
//   //   if (savedPriv != null && savedPub != null) {
//   //     final privRaw = base64Decode(savedPriv);
//   //     final pubRaw = base64Decode(savedPub);
//   //     final publicKey = crypto.SimplePublicKey(pubRaw, type: crypto.KeyPairType.p256);
//   //     return crypto.SimpleKeyPairData(privRaw, publicKey: publicKey, type: crypto.KeyPairType.p256);
//   //   }
//   //   final pair = await algorithm.newKeyPair();
//   //   final privRaw = await pair.extractPrivateKeyBytes();
//   //   final pubKey = await pair.extractPublicKey();
//   //   final pubRaw = pubKey.bytes;
//   //   await _k.write(key: _privKey, value: base64Encode(privRaw));
//   //   await _k.write(key: _pubKey, value: base64Encode(pubRaw));
//   //   return pair;
//   // }
// }