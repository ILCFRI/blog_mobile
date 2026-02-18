import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/ui_helpers.dart';

class EditBlogScreen extends StatefulWidget {
  final Map<String, dynamic> blog;
  final ScrollController? scrollController;

  const EditBlogScreen({
    super.key,
    required this.blog,
    this.scrollController,
  });

  @override
  State<EditBlogScreen> createState() => _EditBlogScreenState();
}

class _EditBlogScreenState extends State<EditBlogScreen> {
  final supabase = Supabase.instance.client;
  final _imagePicker = ImagePicker();

  late TextEditingController _contentController;

  String? _username;
  String? _avatarUrl;

  XFile? _selectedImage;
  String? _existingImageUrl;

  bool isSaving = false;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _contentController =
        TextEditingController(text: widget.blog['content']);
    _existingImageUrl = widget.blog['image_url'];

    _fetchUserProfile();
    _contentController.addListener(() => setState(() {}));
  }

  bool get _canSave =>
      _contentController.text.trim().isNotEmpty ||
      _selectedImage != null ||
      _existingImageUrl != null;

  Future<void> _fetchUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('profiles')
        .select('username, avatar_url')
        .eq('id', user.id)
        .single();

    setState(() {
      _username = data['username'];
      _avatarUrl = data['avatar_url'];
      _isLoadingProfile = false;
    });
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );

    if (picked == null) return;

    setState(() {
      _selectedImage = XFile(picked.path);
      _existingImageUrl = null; // replace old image
    });
  }

  Future<String?> _uploadImage(String userId) async {
    if (_selectedImage == null) return null;

    // Get file bytes
    final bytes = await _selectedImage!.readAsBytes();

    // File extension
    final ext = _selectedImage!.path.split('.').last;

    // Path in Supabase storage
    final path = 'blogs/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    // Upload bytes to Supabase storage
    await supabase.storage.from('blog-images').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: _selectedImage!.mimeType, // optional, detects MIME automatically
      ),
    );

    // Return public URL
    return supabase.storage.from('blog-images').getPublicUrl(path);
  }


  Future<void> _updateBlog() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => isSaving = true);

    try {
      String? imageUrl = _existingImageUrl;

      if (_selectedImage != null) {
        imageUrl = await _uploadImage(user.id);
      }

      await supabase.from('blogs').update({
        'content': _contentController.text.trim(),
        'image_url': imageUrl,
      }).eq('id', widget.blog['id']);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      UiHelpers.showError(context, 'Update failed.');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Widget buildImagePreview(XFile file, {double? height}) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            height: height ?? 150,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        return Image.memory(
          snapshot.data!,
          height: height,
          fit: BoxFit.cover,
        );
      },
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            /// DRAG HANDLE
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            /// HEADER (same as Create Blog)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text(
                  'Edit Blog',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: _canSave && !isSaving ? _updateBlog : null,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            /// USER ROW (same as Create Blog)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage:
                      _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                  child:
                      _avatarUrl == null ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _username ?? 'Unknown user',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _contentController,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Edit content...',
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            /// IMAGE PREVIEW
            if (_selectedImage != null || _existingImageUrl != null) ...[
              const SizedBox(height: 12),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _selectedImage != null
                        ? buildImagePreview(_selectedImage!)
                        : Image.network(_existingImageUrl!),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedImage = null;
                          _existingImageUrl = null;
                        });
                      },
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            /// IMAGE PICKER
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  onPressed: _pickImage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
