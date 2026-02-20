import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blog_mobile/screens/edit_blog_screen.dart';
import 'package:blog_mobile/screens/view_blog_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _blogsChannel;

  List<Map<String, dynamic>> blogs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBlogs();
    _listenToBlogChanges();
  }

  Future<void> refresh() async {
    await _fetchBlogs();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will be signed out of your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  Future<void> _fetchBlogs() async {
    try {
      final data = await supabase
          .from('blogs')
          .select(
            '''
            id,
            title,
            content,
            image_urls,
            created_at,
            user_id,
            profiles(
              username,
              avatar_url
            )
            '''
          )
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        blogs = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  void _listenToBlogChanges() {
    _blogsChannel = supabase
      .channel('public:blogs')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'blogs',
        callback: (payload) {
          _fetchBlogs();
        },
      )
      .subscribe();
  }

  @override
  void dispose() {
    if (_blogsChannel != null) {
      supabase.removeChannel(_blogsChannel!);
    }
    super.dispose();
  }

  Future<void> _deleteBlog(String blogId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete blog?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final blogData = blogs.cast<Map<String, dynamic>?>().firstWhere(
      (b) => b?['id'] == blogId,
      orElse: () => null,
    );
    if (blogData == null) return;

    // Delete all images from storage
    final imageUrls = (blogData['image_urls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [];

    await supabase.from('blogs').delete().eq('id', blogId);

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
        debugPrint('Failed to delete image: $e');
      }
    }

    _fetchBlogs();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blogs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : blogs.isEmpty
          ? const Center(child: Text('No blogs yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: blogs.length,
              itemBuilder: (context, index) {
                final blog = blogs[index];

                final isOwner = 
                  blog['user_id'] == supabase.auth.currentUser?.id;

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ViewBlogScreen(
                          blogId: blog['id'],
                        ),
                      ),
                    );
                  },
                  child: BlogCard(
                    blog: blog,
                    isOwner: isOwner,
                    onRefresh: _fetchBlogs,
                    onDelete: _deleteBlog,
                  ),
                );
              },
            ),
    );
  }
}

class BlogCard extends StatelessWidget {
  final Map<String, dynamic> blog;
  final bool isOwner;
  final VoidCallback onRefresh;
  final Function(String) onDelete;

  const BlogCard({
    super.key, 
    required this.blog,
    required this.isOwner,
    required this.onRefresh,
    required this.onDelete
    });

  @override
  Widget build(BuildContext context) {
    final title = blog['title'] as String?;
    final profile = blog['profiles'];
    final username = profile?['username'] as String?;
    final avatarUrl = profile?['avatar_url'] as String?;
    final imageUrls = List<String>.from(blog['image_urls'] ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage:
                      avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, size: 20)
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username ?? 'Unknown user',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatDate(blog['created_at']),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (isOwner)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final updated = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true, 
                          builder: (_) => EditBlogScreen(blog: blog),
                        );

                        if (updated == true) {
                          onRefresh();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.red
                      ),
                      onPressed: () {
                        onDelete(blog['id']);
                      },
                    ),
                  ],
                )

              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title.trim().isNotEmpty) ...[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                ],
                
                Text(
                  blog['content'] ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          if (imageUrls.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: Stack(
              children: [
                Image.network(
                  imageUrls.first,
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
                  errorBuilder: (context, _, _) => const SizedBox(
                    height: 180,
                    child: Icon(Icons.broken_image),
                  ),
                ),
                if (imageUrls.length > 1)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${imageUrls.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String timestamp) {
    final date = DateTime.parse(timestamp);
    return '${date.month}/${date.day}/${date.year}';
  }
}
