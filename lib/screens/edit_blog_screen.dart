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

  final List<XFile> _newImages = [];           
  List<String> _existingImageUrls = [];  

  bool isSaving = false;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.blog['content']);

    // Load existing image URLs from blog
    _existingImageUrls = (widget.blog['image_urls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    _fetchUserProfile();
    _contentController.addListener(() => setState(() {}));
  }

  bool get _canSave =>
      _contentController.text.trim().isNotEmpty ||
      _newImages.isNotEmpty ||
      _existingImageUrls.isNotEmpty;

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

  Future<void> _pickImages() async {
    final picked = await _imagePicker.pickMultiImage();
    if (picked.isEmpty) return;
    setState(() => _newImages.addAll(picked));
  }

  Future<List<String>> _uploadNewImages(String userId) async {
    final List<String> urls = [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < _newImages.length; i++) {
      final image = _newImages[i];
      final bytes = await image.readAsBytes();
      final mimeType = image.mimeType ?? 'image/jpeg';
      final ext = mimeType.split('/').last;
      final path = 'blogs/$userId/${timestamp}_$i.$ext';

      await supabase.storage.from('blog-images').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: mimeType),
      );

      urls.add(supabase.storage.from('blog-images').getPublicUrl(path));
    }

    return urls;
  }

  Future<void> _updateBlog() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => isSaving = true);

    try {
      final newUrls = await _uploadNewImages(user.id);
      final allImageUrls = [..._existingImageUrls, ...newUrls];

      await supabase.from('blogs').update({
        'content': _contentController.text.trim(),
        'image_urls': allImageUrls,
      }).eq('id', widget.blog['id']);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      UiHelpers.showError(context, 'Update failed.');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Widget _buildImagePreview(XFile file) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
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

    // Combined preview list: existing URLs + new XFiles
    final totalImages = _existingImageUrls.length + _newImages.length;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            // Drag handle
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

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text('Edit Blog',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: _canSave && !isSaving ? _updateBlog : null,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // User row + content
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
                      Text(_username ?? 'Unknown user',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
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

            // Image grid preview
            if (totalImages > 0) ...[
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: totalImages,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final isExisting = index < _existingImageUrls.length;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: isExisting
                            ? Image.network(
                                _existingImageUrls[index],
                                fit: BoxFit.cover,
                              )
                            : _buildImagePreview(
                                _newImages[index - _existingImageUrls.length],
                              ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isExisting) {
                                _existingImageUrls.removeAt(index);
                              } else {
                                _newImages.removeAt(
                                    index - _existingImageUrls.length);
                              }
                            });
                          },
                          child: const CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],

            const SizedBox(height: 12),

            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  onPressed: _pickImages,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}