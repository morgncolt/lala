import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';
import 'mock_euthereumservice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'hashtag_utils.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'map_screen.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math; // use math.Random, math.min, math.max
import 'package:latlong2/latlong.dart';

class CifScreen extends StatefulWidget {
  const CifScreen({Key? key}) : super(key: key);

  @override
  _CifScreenState createState() => _CifScreenState();
}

class _CifScreenState extends State<CifScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _minVotersController = TextEditingController();

  bool _isPublic = true;
  bool _isLoading = false;
  String? _linkedHashtag;

  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedImages = [];

  List<Map<String, dynamic>> _projects = [];
  String? _selectedPropertyId;
  bool _isPropertyVerified = false;
  List<Map<String, dynamic>> _userProperties = []; // [{'id': 'LL-XXX-YYYY', 'verified': true}]
  final String projectId = DateTime.now().millisecondsSinceEpoch.toString();
  bool _showSubmitForm = false;
  double? _costPerVoter;

  final _verificationCache = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _amountController.text = '50000';
    loadCifProjects();
    _loadUserProperties();
  }

  // ---------- Data Loading ----------

  Future<void> _loadUserProperties() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('regions')
          .get();

      final loaded = <Map<String, dynamic>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final id = (data['title_number'] ?? doc.id).toString();
        final verified = await _verifyPropertyOnBlockchain(id);
        loaded.add({'id': id, 'verified': verified});
      }

      setState(() => _userProperties = loaded);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load properties: $e')),
      );
    }
  }

 Future<void> loadCifProjects() async {
    // Show all public projects from all users
    final snapshot = await FirebaseFirestore.instance
        .collectionGroup('projects')
        .where('isPublic', isEqualTo: true)
        // Optional but recommended for stable ordering/pagination:
        // .orderBy('createdAt', descending: true)
        .get();

    setState(() {
      _projects = snapshot.docs.map((doc) {
        final data = doc.data();
        // Safety fallback if some old docs don’t have ownerId
        data['ownerId'] ??= doc.reference.parent.parent?.id;
        return Map<String, dynamic>.from(data);
      }).toList();
    });
  }


  Future<void> saveCifProject(String userId, Map<String, dynamic> projectData) async {
    final docRef = FirebaseFirestore.instance
        .collection('cif_projects')
        .doc(userId)
        .collection('projects')
        .doc(projectData['id'] as String);
    await docRef.set(projectData);
  }

  Future<void> deleteCifProject(String projectId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('cif_projects')
        .doc(user.uid)
        .collection('projects')
        .doc(projectId)
        .delete();

    setState(() {
      _projects.removeWhere((proj) => proj['id'] == projectId);
    });
  }

  // ---------- Blockchain Verify (cached) ----------

  Future<bool> _verifyPropertyOnBlockchain(String propertyId) async {
    try {
      if (_verificationCache.containsKey(propertyId)) {
        return _verificationCache[propertyId]!;
      }

      if (!propertyId.startsWith('LL-') || propertyId.length < 10) {
        _verificationCache[propertyId] = false;
        return false;
      }

      final url = 'http://10.0.2.2:4000/api/landledger/verify/$propertyId';
      final response = await http
          .get(Uri.parse(url), headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      bool ok = false;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        ok = data['exists'] == true;
      }
      _verificationCache[propertyId] = ok;
      return ok;
    } catch (e) {
      _verificationCache[propertyId] = false;
      return false;
    }
  }

  void clearVerificationCache() => _verificationCache.clear();

  // ---------- Helpers ----------

  String _generateProjectId(bool isPublic, String propertyId) {
    // LL-<PB|PV>-<City>-<last4><ts4>
    String city = 'GEN';
    try {
      final parts = propertyId.split('-');
      if (parts.length >= 2) city = parts[1];
    } catch (_) {}

    String lastFour = propertyId.length >= 4
        ? propertyId.substring(propertyId.length - 4)
        : _randomString(4);

    final typePrefix = isPublic ? 'PB' : 'PV';
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final ts4 = ts.substring(ts.length - 4);

    return 'LL-$typePrefix-$city-$lastFour$ts4';
  }

  String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = math.Random();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
  }

  void _updateCostPerVoter() {
    final amount = double.tryParse(_amountController.text);
    final voters = int.tryParse(_minVotersController.text);
    if (amount != null && voters != null && voters > 0) {
      setState(() => _costPerVoter = amount / voters);
    } else {
      setState(() => _costPerVoter = null);
    }
  }

  void _toggleSubmitForm() => setState(() => _showSubmitForm = !_showSubmitForm);

  List<Map<String, dynamic>> get _filteredPublicProjects =>
      _projects.where((p) => p['isPublic'] == true).toList();

  List<Map<String, dynamic>> get _filteredPrivateProjects =>
      _projects.where((p) => p['isPublic'] == false).toList();

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    if (picked != null) setState(() => _selectedImages = picked);
  }

  Future<List<String>> _uploadImages(String projectId, String userId) async {
    final storage = FirebaseStorage.instance;
    final urls = <String>[];
    for (var image in _selectedImages) {
      final ref = storage.ref().child('cif_projects/$userId/$projectId/${image.name}');
      await ref.putFile(File(image.path));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  // ---------- Submit public/private project ----------

  Future<void> _submitContract() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_isPublic && _selectedPropertyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a property for this private project.")),
      );
      return;
    }

    if (_isPublic) {
      final mv = int.tryParse(_minVotersController.text) ?? 0;
      if (mv <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Minimum voters must be greater than 0.")),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final eth = Provider.of<MockEthereumService>(context, listen: false);
      await eth.createContract(
        _isPublic,
        _descriptionController.text,
        EtherAmount.fromUnitAndValue(
          EtherUnit.ether,
          int.parse(_amountController.text),
        ),
      );

      final photoUrls = await _uploadImages(projectId, user.uid);
      final goalAmount = int.parse(_amountController.text);
      final minVoters = _isPublic ? int.parse(_minVotersController.text) : 0;
      final amountPerVote = _isPublic ? (goalAmount / minVoters).ceil() : 0;

      String? hashtag;
      if (!_isPublic && _selectedPropertyId != null) {
        final propertyDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('regions')
            .where('title_number', isEqualTo: _selectedPropertyId)
            .limit(1)
            .get();

        if (propertyDoc.docs.isNotEmpty) {
          final rawAlias = propertyDoc.docs.first.data()['alias'];
          hashtag = (rawAlias == null) ? null : rawAlias.toString().replaceAll('#', '');
        }
      }

      final newProject = <String, dynamic>{
        'id': _generateProjectId(_isPublic, _selectedPropertyId ?? 'LL-GEN-0000'),
        'ownerId': user.uid,
        'title': _isPublic
            ? 'Community Project ${DateTime.now().year}'
            : 'Private Project ${_selectedPropertyId ?? ''}',
        'description': _descriptionController.text,
        'amount': goalAmount,
        'isPublic': _isPublic,
        'votes': 0,
        'funded': 0,
        'goal': goalAmount,
        'requiredVotes': minVoters,
        'amountPerVote': amountPerVote,
        'voters': <String>[],
        'image': '🛠️',
        'status': 'Pending',
        'hashtag': hashtag,
        'photoUrls': photoUrls,
        'propertyId': _selectedPropertyId,
        'isVerified': _isPropertyVerified,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await saveCifProject(user.uid, newProject);
      await loadCifProjects();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isPublic
            ? "Project submitted for community voting!"
            : "Private project created and verified!")),
      );

      _descriptionController.clear();
      _selectedImages.clear();
      _minVotersController.clear();
      _costPerVoter = null;
      _selectedPropertyId = null;
      _isPropertyVerified = false;
      _toggleSubmitForm();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---------- Voting ----------

  Future<void> _handleVote(Map<String, dynamic> project) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ownerId = (project['ownerId'] as String?) ?? user.uid;
    final projectId = project['id'] as String;

    final docRef = FirebaseFirestore.instance
        .collection('cif_projects')
        .doc(ownerId)
        .collection('projects')
        .doc(projectId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw Exception('Project not found');

        final data = snap.data() as Map<String, dynamic>;
        final List<dynamic> voters = List.from(data['voters'] ?? []);
        if (voters.contains(user.uid)) {
          throw StateError('already_voted');
        }

        final int votes = (data['votes'] ?? 0) + 1;
        final int requiredVotes = ((data['requiredVotes'] ?? 0) as int) - 1;
        final int amountPerVote = (data['amountPerVote'] ?? 0) as int;
        final int goal = (data['goal'] ?? 0) as int;
        final int currentFunded = (data['funded'] ?? 0) as int;

        final int newRequired = math.max(requiredVotes, 0);
        final int newFunded = math.min(currentFunded + amountPerVote, goal);
        final bool completed = (newFunded >= goal) || (newRequired == 0);
        final String newStatus = completed ? 'Completed' : (data['status'] ?? 'Pending');

        tx.update(docRef, {
          'votes': votes,
          'requiredVotes': newRequired,
          'funded': newFunded,
          'voters': FieldValue.arrayUnion([user.uid]),
          'status': newStatus,
        });
      });

      // optimistic local update
      setState(() {
        final i = _projects.indexWhere((p) => p['id'] == project['id']);
        if (i != -1) {
          final updated = Map<String, dynamic>.from(_projects[i]);
          final int goal = (updated['goal'] ?? 0) as int;
          final int amountPerVote = (updated['amountPerVote'] ?? 0) as int;

          updated['votes'] = (updated['votes'] ?? 0) + 1;
          updated['requiredVotes'] = math.max((updated['requiredVotes'] ?? 0) - 1, 0);
          updated['funded'] = math.min((updated['funded'] ?? 0) + amountPerVote, goal);

          final List<dynamic> voters = List.from(updated['voters'] ?? []);
          voters.add(user.uid);
          updated['voters'] = voters;

          final bool completed = (updated['funded'] >= goal) || (updated['requiredVotes'] == 0);
          updated['status'] = completed ? 'Completed' : (updated['status'] ?? 'Pending');

          _projects[i] = updated;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vote recorded!')),
      );
    } on StateError catch (e) {
      if (e.message == 'already_voted') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You've already voted on this project.")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voting failed: $e')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voting failed: $e')),
      );
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Community Investment Fund', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.people)),
            Tab(icon: Icon(Icons.lock)),
            Tab(icon: Icon(Icons.engineering)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCommunityProjectsTab(),
          _buildPrivateProjectsTab(),
          _buildContractorsTab(),
        ],
      ),
    );
  }

  Widget _buildCommunityProjectsTab() {
    return Container(
      color: Colors.black,
      child: RefreshIndicator(
        onRefresh: () async => await loadCifProjects(),
        child: _filteredPublicProjects.isEmpty
            ? _buildEmptyState(
                icon: Icons.people_outline,
                title: "No Community Projects",
                description: "Be the first to submit a project for community voting",
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredPublicProjects.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _buildProjectCard(_filteredPublicProjects[index], true),
              ),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project, bool isPublic) {
    final List<dynamic> photoUrls = project['photoUrls'] ?? [];
    final String llId = (project['propertyId'] ?? '').toString();
    final String hashtag = (project['hashtag'] ?? '').toString();
    final String title = (project['title'] ?? 'Untitled Project').toString();
    final String status = (project['status'] ?? 'Pending').toString();

    final int funded = (project['funded'] ?? 0) as int;
    final int goal = (project['goal'] ?? 0) as int;
    final double progress = isPublic && goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;
    final String progressPercent = (progress * 100).toStringAsFixed(1);

    final currentUser = FirebaseAuth.instance.currentUser;
    final bool isOwner = (project['ownerId'] == currentUser?.uid);

    final bool alreadyVoted = (project['voters'] ?? []).contains(currentUser?.uid);
    final bool goalReached = funded >= goal && goal > 0;
    final bool targetReached = (project['requiredVotes'] ?? 0) <= 0;
    final bool canVote = !alreadyVoted && !goalReached && !targetReached;

    return Card(
      color: Colors.grey[900],
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!isPublic)
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[800],
                image: photoUrls.isNotEmpty
                    ? DecorationImage(image: NetworkImage(photoUrls.first), fit: BoxFit.cover)
                    : null,
              ),
              child: photoUrls.isEmpty
                  ? const Center(child: Icon(Icons.photo_camera, size: 50, color: Colors.grey))
                  : const SizedBox.shrink(),
            ),

          if (isPublic && photoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PageView.builder(
                  itemCount: photoUrls.length,
                  itemBuilder: (context, index) => Image.network(
                    photoUrls[index],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey[800], child: const Center(child: Icon(Icons.broken_image))),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),

          if (llId.isNotEmpty || hashtag.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (llId.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
                    child: Text('LL ID: $llId', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                if (hashtag.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      if (llId.isNotEmpty) {
                        await _searchPolygonByLlId(context, llId, hashtag);
                      } else {
                        await handleHashtagTap(context, hashtag.replaceFirst('#', ''));
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue[900], borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.tag, size: 14, color: Colors.blueAccent),
                        const SizedBox(width: 4),
                        Text(hashtag.startsWith('#') ? hashtag.substring(1) : hashtag,
                            style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
                      ]),
                    ),
                  ),
              ]),
            ),

          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              children: buildTextWithHashtag(context, (project['description'] ?? '').toString()),
            ),
          ),
          const SizedBox(height: 16),

          if (isPublic) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("$progressPercent% Funded",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text("$funded CFA / $goal CFA", style: const TextStyle(color: Colors.grey)),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[800],
              color: Colors.blue,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),

            Row(children: [
              _buildStatItem(Icons.thumb_up, "${project['votes'] ?? 0} Votes"),
              const SizedBox(width: 16),
              _buildStatItem(Icons.group, "${project['requiredVotes'] ?? 'N/A'} Target"),
              const Spacer(),
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => deleteCifProject(project['id'] as String),
                ),
            ]),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canVote ? Colors.blue : Colors.grey[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: canVote ? () => _handleVote(project) : null,
                child: Text(
                  alreadyVoted
                      ? "YOU'VE VOTED"
                      : (goalReached || targetReached)
                          ? "VOTING CLOSED"
                          : "VOTE FOR THIS PROJECT",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ] else ...[
            Row(children: [
              Chip(
                label: Text(status, style: const TextStyle(color: Colors.white)),
                backgroundColor: status == 'Completed'
                    ? Colors.green[800]!
                    : status == 'In Progress'
                        ? Colors.blue[800]!
                        : Colors.orange[800]!,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => deleteCifProject(project['id'] as String),
              ),
            ]),
            const SizedBox(height: 8),
            if (project['contractor'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text("Contractor: ${project['contractor']}", style: const TextStyle(color: Colors.grey)),
                ]),
              ),
            if (project['estimatedCompletion'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text("Est. Completion: ${project['estimatedCompletion']}",
                      style: const TextStyle(color: Colors.grey)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }

  Future<void> _searchPolygonByLlId(BuildContext context, String llId, String hashtag) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('regions')
          .where('title_number', isEqualTo: llId)
          .limit(1)
          .get();

      Navigator.of(context).pop();

      if (query.docs.isEmpty) {
        await handleHashtagTap(context, hashtag.replaceFirst('#', ''));
        return;
      }

      final data = query.docs.first.data();
      final coordinates = data['coordinates'] as List?;
      if (coordinates == null || coordinates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No polygon coordinates found for $llId")),
        );
        return;
      }

      final polygonCoords = coordinates.map((c) => LatLng(c['lat'], c['lng'])).toList();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapScreen(
            regionId: data['region'] ?? '',
            geojsonPath: '',
            highlightPolygon: polygonCoords,
          ),
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error finding polygon: $e")),
      );
    }
  }

  Widget _buildPrivateProjectsTab() {
    return Stack(children: [
      Container(
        color: Colors.black,
        child: _filteredPrivateProjects.isEmpty
            ? _buildEmptyState(
                icon: Icons.folder_special,
                title: "No Private Projects",
                description: "Create your first private project",
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredPrivateProjects.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _buildProjectCard(_filteredPrivateProjects[index], false),
              ),
      ),
      if (_showSubmitForm)
        GestureDetector(
          onTap: _toggleSubmitForm,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(child: SingleChildScrollView(child: _buildSubmitForm())),
          ),
        ),
      Positioned(
        bottom: 20,
        right: 20,
        child: FloatingActionButton(
          backgroundColor: Colors.grey[800],
          onPressed: _toggleSubmitForm,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    ]);
  }

  Widget _buildContractorsTab() {
    final contractors = [
      {
        'id': 'contractor_001',
        'name': 'Bako Engineering',
        'specialty': 'Water Systems',
        'rating': 4.5,
        'location': 'Douala, Cameroon',
        'profileImage': 'https://via.placeholder.com/100x100.png?text=B',
        'completedProjects': 42,
      },
      {
        'id': 'contractor_002',
        'name': 'Solar Works Africa',
        'specialty': 'Solar Installations',
        'rating': 4.8,
        'location': 'Kigali, Rwanda',
        'profileImage': 'https://via.placeholder.com/100x100.png?text=S',
        'completedProjects': 37,
      },
    ];

    return Container(
      color: Colors.black,
      child: contractors.isEmpty
          ? _buildEmptyState(
              icon: Icons.engineering,
              title: "No Contractors Available",
              description: "Check back later for verified contractors",
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: contractors.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) => _buildContractorCard(contractors[index]),
            ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String description}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.grey),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(color: Colors.grey)),
    ]);
  }

  Widget _buildContractorCard(Map<String, dynamic> contractor) {
    return Card(
      color: Colors.grey[900],
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(image: NetworkImage(contractor['profileImage']), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(contractor['name'],
                    style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(contractor['specialty'], style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(contractor['location'], style: const TextStyle(color: Colors.grey)),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _buildContractorStat("${contractor['rating']}", "Rating", Icons.star, Colors.amber),
            const SizedBox(width: 16),
            _buildContractorStat("${contractor['completedProjects']}", "Projects", Icons.assignment_turned_in, Colors.blue),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Application process initiated")),
                );
              },
              child: const Text("APPLY", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildContractorStat(String value, String label, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    ]);
  }

  Widget _buildSubmitForm() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(16)),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Create New Project",
                style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _toggleSubmitForm),
          ]),
          const SizedBox(height: 20),
          TextFormField(
            controller: _descriptionController,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration("Project Description", hint: "Describe what needs to be done..."),
            maxLines: 3,
            validator: (val) => (val == null || val.isEmpty) ? "Required" : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration("Estimated Cost (CFA)", prefixText: "CFA "),
            keyboardType: TextInputType.number,
            onChanged: (_) => _updateCostPerVoter(),
            validator: (val) {
              final x = int.tryParse(val ?? '');
              if (x == null || x <= 0) return "Enter a number > 0";
              return null;
            },
          ),
          const SizedBox(height: 16),

          if (_isPublic) ...[
            TextFormField(
              controller: _minVotersController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration("Minimum Voters Required", hint: "100"),
              keyboardType: TextInputType.number,
              onChanged: (_) => _updateCostPerVoter(),
              validator: (val) {
                final x = int.tryParse(val ?? '');
                if (x == null || x <= 0) return "Enter a number > 0";
                return null;
              },
            ),
            const SizedBox(height: 8),
            if (_costPerVoter != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue[900], borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Text("CFA ${_costPerVoter!.toStringAsFixed(2)} per vote",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ]),
              ),
            const SizedBox(height: 16),
          ],

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[700]!),
            ),
            child: Row(children: [
              Icon(_isPublic ? Icons.public : Icons.lock_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isPublic ? "Public Project" : "Private Project",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(
                    _isPublic ? "Community will vote on this project" : "Only visible to you and approved contractors",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ]),
              ),
              Switch(
                value: _isPublic,
                onChanged: (v) {
                  setState(() {
                    _isPublic = v;
                    if (!_isPublic) {
                      _minVotersController.clear();
                      _costPerVoter = null;
                    }
                  });
                },
                activeColor: Colors.blue,
              ),
            ]),
          ),
          const SizedBox(height: 16),

          if (!_isPublic && _userProperties.isNotEmpty) ...[
            const Text("Linked Property (LL ID)",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: _dropdownDecoration(),
              dropdownColor: Colors.grey[900],
              style: const TextStyle(color: Colors.white),
              value: _selectedPropertyId,
              items: _userProperties.map<DropdownMenuItem<String>>((prop) {
                final id = prop['id'] as String;
                final isVerified = (prop['verified'] ?? false) as bool;
                return DropdownMenuItem<String>(
                  value: id,
                  child: Row(children: [
                    Icon(isVerified ? Icons.verified : Icons.warning,
                        color: isVerified ? Colors.green : Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Text(id, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isVerified ? Colors.green : Colors.white)),
                  ]),
                );
              }).toList(),
              onChanged: (val) async {
                if (val == null) return;
                setState(() {
                  _selectedPropertyId = val;
                  _isPropertyVerified = false;
                });
                final verified = await _verifyPropertyOnBlockchain(val);
                setState(() => _isPropertyVerified = verified);
              },
            ),
            const SizedBox(height: 8),
            if (_selectedPropertyId != null)
              Text(
                _isPropertyVerified ? "✅ Property verified on blockchain" : "⚠️ Property not verified",
                style: TextStyle(color: _isPropertyVerified ? Colors.green : Colors.orange, fontSize: 12),
              ),
            const SizedBox(height: 16),
          ],

          const Text("Project Photos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.photo_library, color: Colors.white),
              label: const Text("Add Photos", style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Colors.grey),
              ),
              onPressed: _pickImages,
            ),
          ),
          if (_selectedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text("${_selectedImages.length} photo(s) selected", style: const TextStyle(color: Colors.grey)),
            ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isLoading ? null : _submitContract,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("SUBMIT PROJECT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------- UI helpers ----------

  InputDecoration _inputDecoration(String label, {String? hint, String? prefixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixText: prefixText,
      prefixStyle: const TextStyle(color: Colors.white),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.grey)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.grey)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white)),
      filled: true,
      fillColor: Colors.grey[800],
    );
  }

  InputDecoration _dropdownDecoration() {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.grey)),
      filled: true,
      fillColor: Colors.grey[800],
    );
  }
}
