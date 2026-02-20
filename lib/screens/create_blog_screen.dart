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
  
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _imagePicker = ImagePicker();

  String? _username;
  String? _avatarUrl;

  final List<XFile> _selectedImages = [];
  
  bool isPosting = false;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _titleController.addListener(() => setState(() {}));
    _contentController.addListener(() => setState(() {}));
  }

  bool get _canPost => 
    _titleController.text.trim().isNotEmpty &&
    _contentController.text.trim().isNotEmpty || _selectedImages.isNotEmpty;
  
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
    final pickedImages = await _imagePicker.pickMultiImage();

    if (pickedImages.isEmpty) return;

    setState(() {
      _selectedImages.addAll(pickedImages);
    });
  }

  Future<List<String>> _uploadImages(String userId) async {
    final List<String> imageUrls = [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < _selectedImages.length; i++) {
      final image = _selectedImages[i];
      final bytes = await image.readAsBytes();
      final mimeType = image.mimeType ?? 'image/jpeg';
      final fileExt = mimeType.split('/').last;

      final filePath = 'blogs/$userId/${timestamp}_$i.$fileExt'; 
      await supabase.storage.from('blog-images').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: image.mimeType,
        ),
      );

      final publicUrl =
          supabase.storage.from('blog-images').getPublicUrl(filePath);
      imageUrls.add(publicUrl);
    }

    return imageUrls;
  }

  Future<void> _createBlog() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_titleController.text.trim().isEmpty && 
        _contentController.text.trim().isEmpty && 
        _selectedImages.isEmpty) {
      UiHelpers.showError(context, 'Please add content or images.');
      return;
    }

    setState(() => isPosting = true);

    try {
      final imageUrls = await _uploadImages(user.id);

      await supabase.from('blogs').insert({
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'image_urls': imageUrls,
        'user_id': user.id,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blog post created!')),
      );
      
      Navigator.pop(context, true);
    } catch (e) {
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
    _titleController.dispose();
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
                      controller: _titleController,
                      maxLength: 100,
                      decoration: InputDecoration(
                        hintText: 'Title',
                        border: InputBorder.none,
                      ),
                    ),

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
          if (_selectedImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedImages.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final image = _selectedImages[index];

                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: buildImagePreview(image),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedImages.removeAt(index);
                          });
                        },
                        child: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 16, color: Colors.white),
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
                  icon: Icon(Icons.image_outlined),
                  onPressed: _pickImages,
                )
              ],
            )
        ],
      )
    );
  }
}