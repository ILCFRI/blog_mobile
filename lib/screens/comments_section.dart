import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  XFile? _pickedImage;

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
          image_url,
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

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _pickedImage = XFile(picked.path);
      });
    }
  }

  Future<String?> _uploadImage(String userId) async {
    if (_pickedImage == null) return null;

    final bytes = await _pickedImage!.readAsBytes();
    final fileExt = _pickedImage!.path.split('.').last;
    final filePath =
        'comments/${widget.blogId}/$userId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    await supabase.storage.from('blog-images').uploadBinary(
      filePath,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: _pickedImage!.mimeType,
      ),
    );

    return supabase.storage.from('blog-images').getPublicUrl(filePath);
  }



  Future<void> _addOrEditComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pickedImage == null) return;

    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      String? imageUrl;
      if (_pickedImage != null) {
        imageUrl = await _uploadImage(user.id);
      }

      if (_editingCommentId != null) {
        // Edit
        final updateData = {'comment': text, 'image_url': imageUrl};
        if (imageUrl == null) updateData['image_url'] = null;

        await supabase
            .from('comments')
            .update(updateData)
            .eq('id', _editingCommentId!);
        _editingCommentId = null;
      } else {
        // Add
        await supabase.from('comments').insert({
          'blog_id': widget.blogId,
          'user_id': user.id,
          'comment': text,
          'image_url': imageUrl,
        });
      }

      _controller.clear();
      _pickedImage = null;

      // Refresh comments immediately after posting
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

    final imageUrl = comment['image_url'] as String?;

    // Delete comment row from database
    await supabase.from('comments').delete().eq('id', id);

    // Delete image from storage if it exists
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(imageUrl);
        final segments = uri.pathSegments;
        final bucketIndex = segments.indexOf('blog-images'); // match your bucket name
        if (bucketIndex != -1) {
          final filePath = segments.sublist(bucketIndex + 1).join('/');
          await supabase.storage.from('blog-images').remove([filePath]);
        }
      } catch (e) {
        debugPrint('Failed to delete comment image: $e');
      }
    }

    // Refresh comments
    _fetchComments();
  }

  void _startEdit(Map<String, dynamic> comment) {
    final contentController =
        TextEditingController(text: comment['comment'] ?? '');
    XFile? selectedImage;
    String? existingImageUrl = comment['image_url'];

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            Future<void> pickModalImage() async {
              final picked =
                  await ImagePicker().pickImage(source: ImageSource.gallery);

              if (!sheetContext.mounted) return;

              if (picked != null) {
                setModalState(() {
                  selectedImage = XFile(picked.path);
                  existingImageUrl = null;
                });
              }
            }

            Future<void> saveEdit() async {
              final user = supabase.auth.currentUser;
              if (user == null) return;

              String? imageUrl = existingImageUrl;

              if (selectedImage != null) {
                final ext = selectedImage!.path.split('.').last;
                final path =
                    'comments/${widget.blogId}/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

                await supabase.storage.from('blog-images').uploadBinary(
                  path,
                  await selectedImage!.readAsBytes(),
                  fileOptions: FileOptions(
                    upsert: true,
                    contentType: selectedImage!.mimeType,
                  ),
                );


                imageUrl =
                    supabase.storage.from('blog-images').getPublicUrl(path);
              }

              await supabase.from('comments').update({
                'comment': contentController.text.trim(),
                'image_url': imageUrl,
              }).eq('id', comment['id']);

              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext, true);

              if (mounted) _fetchComments();
            }

            final canSave =
                contentController.text.trim().isNotEmpty ||
                    selectedImage != null ||
                    existingImageUrl != null;

            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.9,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                        ),
                        const Text(
                          'Edit Comment',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
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

                    if (selectedImage != null || existingImageUrl != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: selectedImage != null
                                ? buildImagePreview(selectedImage!)
                                : Image.network(existingImageUrl!),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  selectedImage = null;
                                  existingImageUrl = null;
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
                      ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image_outlined),
                          onPressed: pickModalImage,
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
        const Text('Comments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              final imageUrl = comment['image_url'];

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
                                        fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                if (isOwner)
                                  PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'edit') _startEdit(comment);
                                      if (val == 'delete') _deleteComment(comment['id']);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(comment['comment'] ?? ''),
                            if (imageUrl != null && imageUrl.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 400,
                                    minHeight: 100,
                                  ),
                                  child: Image.network(
                                    imageUrl,
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return const SizedBox(
                                        height: 180,
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    },
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image),
                                  ),
                                )
                              ),
                            ]
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

        if (_pickedImage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Stack(
              children: [
                buildImagePreview(_pickedImage!, height: 100),
                Positioned(
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() => _pickedImage = null),
                  ),
                ),
              ],
            ),
          ),

        Row(
          children: [
            IconButton(icon: const Icon(Icons.image), onPressed: _pickImage),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: _editingCommentId != null ? 'Edit comment...' : 'Write a comment...',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _addOrEditComment),
          ],
        ),
      ],
    );
  }
}
