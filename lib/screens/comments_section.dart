import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class CommentsSection extends StatefulWidget {
  final String blogId;

  const CommentsSection({super.key, required this.blogId});

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  RealtimeChannel? _commentsChannel;

  List<Map<String, dynamic>> comments = [];
  bool isLoading = true;
  String? _editingCommentId;
  final List<XFile> _pickedImages = [];

  @override
  void initState() {
    super.initState();
    _fetchComments();
    _listenToCommentsRealtime();
  }

  Future<void> _fetchComments() async {
    final data = await supabase
        .from('comments')
        .select('''
          id,
          comment,
          image_urls,
          user_id,
          created_at,
          profiles(
            username,
            avatar_url
          )
        ''')
        .eq('blog_id', widget.blogId)
        .order('created_at');

    if (!mounted) return;

    setState(() {
      comments = List<Map<String, dynamic>>.from(data);
      isLoading = false;
    });
  }

  void _listenToCommentsRealtime() {
    _commentsChannel = supabase
        .channel('comments-${widget.blogId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'blog_id',
            value: widget.blogId,
          ),
          callback: (_) => _fetchComments(),
        )
        .subscribe();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    setState(() => _pickedImages.addAll(picked));
  }

  Future<List<String>> _uploadImages(String userId) async {
    final List<String> urls = [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < _pickedImages.length; i++) {
      final image = _pickedImages[i];
      final bytes = await image.readAsBytes();
      final mimeType = image.mimeType ?? 'image/jpeg';
      final ext = mimeType.split('/').last;
      final filePath =
          'comments/${widget.blogId}/$userId/${timestamp}_$i.$ext';

      await supabase.storage.from('blog-images').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: mimeType),
      );

      urls.add(supabase.storage.from('blog-images').getPublicUrl(filePath));
    }

    return urls;
  }

  Future<void> _addOrEditComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pickedImages.isEmpty) return;

    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final imageUrls = await _uploadImages(user.id);

      if (_editingCommentId != null) {
        await supabase.from('comments').update({
          'comment': text,
          'image_urls': imageUrls,
        }).eq('id', _editingCommentId!);
        _editingCommentId = null;
      } else {
        await supabase.from('comments').insert({
          'blog_id': widget.blogId,
          'user_id': user.id,
          'comment': text,
          'image_urls': imageUrls,
        });
      }

      _controller.clear();
      _pickedImages.clear();

      await _fetchComments();
    } catch (e) {
      debugPrint('Failed to post comment: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _deleteComment(String id) async {
    final comment = comments.firstWhere(
      (c) => c['id'] == id,
      orElse: () => <String, dynamic>{},
    );

    final imageUrls = List<String>.from(comment['image_urls'] ?? []);

    await supabase.from('comments').delete().eq('id', id);

    for (final imageUrl in imageUrls) {
      try {
        final uri = Uri.parse(imageUrl);
        final segments = uri.pathSegments;
        final bucketIndex = segments.indexOf('blog-images');
        if (bucketIndex != -1) {
          final filePath = segments.sublist(bucketIndex + 1).join('/');
          await supabase.storage.from('blog-images').remove([filePath]);
        }
      } catch (e) {
        debugPrint('Failed to delete comment image: $e');
      }
    }

    _fetchComments();
  }

  void _startEdit(Map<String, dynamic> comment) {
    final contentController =
        TextEditingController(text: comment['comment'] ?? '');
    List<XFile> newImages = [];
    List<String> existingImageUrls =
        List<String>.from(comment['image_urls'] ?? []);

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            Future<void> pickModalImages() async {
              final picked = await ImagePicker().pickMultiImage();
              if (!sheetContext.mounted) return;
              if (picked.isNotEmpty) {
                setModalState(() => newImages.addAll(picked));
              }
            }

            Future<void> saveEdit() async {
              final user = supabase.auth.currentUser;
              if (user == null) return;

              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final List<String> uploadedUrls = [];

              for (int i = 0; i < newImages.length; i++) {
                final image = newImages[i];
                final mimeType = image.mimeType ?? 'image/jpeg';
                final ext = mimeType.split('/').last;
                final path =
                    'comments/${widget.blogId}/${user.id}/${timestamp}_$i.$ext';

                await supabase.storage.from('blog-images').uploadBinary(
                  path,
                  await image.readAsBytes(),
                  fileOptions:
                      FileOptions(upsert: true, contentType: mimeType),
                );

                uploadedUrls.add(
                    supabase.storage.from('blog-images').getPublicUrl(path));
              }

              final allUrls = [...existingImageUrls, ...uploadedUrls];

              await supabase.from('comments').update({
                'comment': contentController.text.trim(),
                'image_urls': allUrls,
              }).eq('id', comment['id']);

              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext, true);
              if (mounted) _fetchComments();
            }

            final totalImages = existingImageUrls.length + newImages.length;
            final canSave =
                contentController.text.trim().isNotEmpty || totalImages > 0;

            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.9,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                        const Text('Edit Comment',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: canSave ? saveEdit : null,
                          child: const Text('Save'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: contentController,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'Edit comment...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),

                    const SizedBox(height: 12),

                    // Image grid for editing (keeps remove buttons)
                    if (totalImages > 0)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: totalImages,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) {
                          final isExisting =
                              index < existingImageUrls.length;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isExisting
                                    ? Image.network(
                                        existingImageUrls[index],
                                        fit: BoxFit.cover,
                                      )
                                    : _buildXFilePreview(newImages[
                                        index - existingImageUrls.length]),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      if (isExisting) {
                                        existingImageUrls.removeAt(index);
                                      } else {
                                        newImages.removeAt(
                                            index - existingImageUrls.length);
                                      }
                                    });
                                  },
                                  child: const CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.black54,
                                    child: Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image_outlined),
                          onPressed: pickModalImages,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildXFilePreview(XFile file, {double? height}) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            height: height ?? 150,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return Image.memory(snapshot.data!, height: height, fit: BoxFit.cover);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_commentsChannel != null) supabase.removeChannel(_commentsChannel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Comments',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),

        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else if (comments.isEmpty)
          const Text('No comments yet')
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: comments.length,
            itemBuilder: (context, index) {
              final comment = comments[index];
              final profile = comment['profiles'];
              final isOwner = comment['user_id'] == currentUserId;
              final imageUrls =
                  List<String>.from(comment['image_urls'] ?? []);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: profile?['avatar_url'] != null
                          ? NetworkImage(profile['avatar_url'])
                          : null,
                      child: profile?['avatar_url'] == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    profile?['username'] ?? 'Unknown',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                ),
                                if (isOwner)
                                  PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'edit') _startEdit(comment);
                                      if (val == 'delete') {
                                        _deleteComment(comment['id']);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete')),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(comment['comment'] ?? ''),

                            // Slideable image viewer
                            if (imageUrls.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _ImageSlider(imageUrls: imageUrls),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

        const SizedBox(height: 12),

        // Picked images preview grid
        if (_pickedImages.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _pickedImages.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildXFilePreview(_pickedImages[index]),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _pickedImages.removeAt(index)),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

        const SizedBox(height: 8),

        // Comment input row
        Row(
          children: [
            IconButton(
                icon: const Icon(Icons.image), onPressed: _pickImages),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: _editingCommentId != null
                      ? 'Edit comment...'
                      : 'Write a comment...',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
                icon: const Icon(Icons.send), onPressed: _addOrEditComment),
          ],
        ),
      ],
    );
  }
}

////////////////////////////////////////////////////////////
/// IMAGE SLIDER WIDGET
////////////////////////////////////////////////////////////

class _ImageSlider extends StatefulWidget {
  final List<String> imageUrls;

  const _ImageSlider({required this.imageUrls});

  @override
  State<_ImageSlider> createState() => _ImageSliderState();
}

class _ImageSliderState extends State<_ImageSlider> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: PageView.builder(
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) =>
                  setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.imageUrls[index],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                            child: CircularProgressIndicator());
                      },
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.imageUrls.length > 1) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.imageUrls.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentIndex == index ? 10 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: _currentIndex == index
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400],
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}