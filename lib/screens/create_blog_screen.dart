import 'dart:typed_data';
import 'package:blog_mobile/utils/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class CreateBlogScreen extends StatefulWidget {
  const CreateBlogScreen({super.key, this.scrollController});
  
  final ScrollController? scrollController;

  @override
  State<CreateBlogScreen> createState() => _CreateBlogScreenState();
}

class _CreateBlogScreenState extends State<CreateBlogScreen> {
  final supabase = Supabase.instance.client;

  final _contentController = TextEditingController();
  final _imagePicker = ImagePicker();

  String? _username;
  String? _avatarUrl;

  XFile? _selectedImage;
  
  bool isPosting = false;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _contentController.addListener(() => setState(() {}));
  }

  bool get _canPost => 
    _contentController.text.trim().isNotEmpty || _selectedImage != null;
  
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
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);

    if (picked == null) return;

    setState(() {
      _selectedImage = XFile(picked.path);
    });
  }

  Future<String?> _uploadImage(String userId) async {
    if (_selectedImage == null) return null;

    // Read image bytes
    final bytes = await _selectedImage!.readAsBytes();

    final fileExt = _selectedImage!.path.split('.').last;
    final filePath =
        'blogs/$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    // Upload using bytes
    await supabase.storage.from('blog-images').uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _selectedImage!.mimeType, // optional, helps with web
          ),
        );

    return supabase.storage.from('blog-images').getPublicUrl(filePath);
  }

  Future<void> _createBlog() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => isPosting = true);

    try {
      final imageUrl = await _uploadImage(user.id);

      await supabase.from('blogs').insert({
        'content': _contentController.text.trim(),
        'image_url': imageUrl,
        'user_id': user.id,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      UiHelpers.showError(context, 'Post failed.');
    } finally {
      if (mounted) setState(() => isPosting = false);
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

    return Container(
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
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)
              ),
            ),
          ),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text(
                  'Create Blog',
                  style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold
                  ),
                ),
                TextButton(
                  onPressed: _canPost && !isPosting ? _createBlog : null, 
                  child: isPosting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Post')
                )
              ], 
          ),
          
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: 
                  _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                child: _avatarUrl == null ? const Icon(Icons.person) : null,
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
                        fontSize: 14
                      )
                    ),
                    const SizedBox(height: 6),

                    TextField(
                      controller: _contentController,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'What\'s new?',
                        border: InputBorder.none,
                      ),
                    )
                  ],
                ) 
              ),
            ],  
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 12),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: buildImagePreview(_selectedImage!),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedImage = null),
                    child: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.black54,
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white
                      )
                    )
                  )
                )
              ],
            ),
          ],
          
          const SizedBox(height: 12),

          Row(
              children: [
                IconButton(
                  icon: Icon(Icons.image_outlined),
                  onPressed: _pickImage,
                )
              ],
            )
        ],
      )
    );
  }
}