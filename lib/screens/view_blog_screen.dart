import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:blog_mobile/screens/comments_section.dart';

class ViewBlogScreen extends StatefulWidget {
  final String blogId;
  

  const ViewBlogScreen({
    super.key,
    required this.blogId,
  });

  @override
  State<ViewBlogScreen> createState() => _ViewBlogScreenState();
}

class _ViewBlogScreenState extends State<ViewBlogScreen> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _blogChannel;

  Map<String, dynamic>? blog;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBlog();
    _listenToBlogRealtime();
  }

  Future<void> _fetchBlog() async {
    final data = await supabase
        .from('blogs')
        .select('''
          id,
          content,
          image_urls,
          created_at,
          user_id,
          profiles(
            username,
            avatar_url
          )
        ''')
        .eq('id', widget.blogId)
        .single();

    if (!mounted) return;

    setState(() {
      blog = data;
      isLoading = false;
    });
  }

  void _listenToBlogRealtime() {
    _blogChannel = supabase
        .channel('blog-${widget.blogId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blogs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.blogId,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              Navigator.pop(context);
            } else {
              _fetchBlog();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_blogChannel != null) {
      supabase.removeChannel(_blogChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (blog == null) {
      return const Scaffold(
        body: Center(child: Text('Blog not found')),
      );
    }

    final List<String> imageUrls =
      (blog!['image_urls'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      [];

    final profile = blog!['profiles'];
    final username = profile?['username'] ?? 'Unknown';
    final avatarUrl = profile?['avatar_url'];

    return Scaffold(
      appBar: AppBar(title: const Text('Blog')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage:
                      avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _formatDate(blog!['created_at']),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Content
            Text(
              blog!['content'] ?? '',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),

            const SizedBox(height: 16),

            // Images
            if (imageUrls.isNotEmpty) ...[
            SizedBox(
              height: 260,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,   // 👈 enables mouse drag on web
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: PageView.builder(
                  itemCount: imageUrls.length,
                  physics: const PageScrollPhysics(),
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: imageUrls[index],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.broken_image),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // ... your page indicator dots
          ],
            const SizedBox(height: 24),
            const Divider(),

            // 👇 COMMENTS
            CommentsSection(blogId: widget.blogId),
          ],
        ),
      ),
    );
  }

  String _formatDate(String timestamp) {
    final date = DateTime.parse(timestamp);
    return '${date.month}/${date.day}/${date.year}';
  }
}

////////////////////////////////////////////////////////////
/// COMMENTS SECTION
////////////////////////////////////////////////////////////


