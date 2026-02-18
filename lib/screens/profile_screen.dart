import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;

  String? username;
  String? avatarUrl;
  bool isLoading = true;
  bool isUploading = false;

  late TextEditingController _usernameController;
  bool isEditingUsername = false;
  bool isSavingUsername = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  // ---------------- FETCH PROFILE ----------------
  Future<void> _fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('profiles')
        .select('username, avatar_url')
        .eq('id', user.id)
        .single();

    if (!mounted) return;

    setState(() {
      username = data['username'];
      avatarUrl = data['avatar_url'];
      _usernameController = TextEditingController(text: username);
      isLoading = false;
    });
  }

  // ---------------- UPDATE USERNAME ----------------
  Future<void> _updateUsername() async {
    final newUsername = _usernameController.text.trim();
    final user = supabase.auth.currentUser;

    if (user == null || newUsername.isEmpty) return;

    setState(() => isSavingUsername = true);

    await supabase
        .from('profiles')
        .update({'username': newUsername})
        .eq('id', user.id);

    if (!mounted) return;

    setState(() {
      username = newUsername;
      isEditingUsername = false;
      isSavingUsername = false;
    });
  }

  // ---------------- PICK & UPLOAD IMAGE ----------------
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image == null) return;

    final user = supabase.auth.currentUser!;
    final bytes = await image.readAsBytes(); // <-- read bytes for web & mobile

    final filePath = 'avatars/${user.id}/avatar.jpg';

    setState(() => isUploading = true);

    await supabase.storage.from('blog-images').uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg', // you can make this dynamic if needed
          ),
        );

    final publicUrl =
        supabase.storage.from('blog-images').getPublicUrl(filePath);

    final cacheBustedUrl =
        '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

    await supabase
        .from('profiles')
        .update({'avatar_url': cacheBustedUrl})
        .eq('id', user.id);

    if (!mounted) return;

    setState(() {
      avatarUrl = cacheBustedUrl;
      isUploading = false;
    });
  }

  // ---------------- VIEW AVATAR ----------------
  void _viewAvatar(BuildContext context) {
    if (avatarUrl == null) return;

    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: Colors.black,
            child: InteractiveViewer(
              child: Center(
                child: Image.network(
                  avatarUrl!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email;

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // PROFILE PHOTO
            Stack(
              children: [
                GestureDetector(
                  onTap: avatarUrl != null ? () => _viewAvatar(context) : null,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage:
                        avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                    child: avatarUrl == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: isUploading ? null : _pickAndUploadImage,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black,
                      child: isUploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // USERNAME (VIEW / EDIT)
            if (isEditingUsername)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Username',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: isSavingUsername
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    onPressed:
                        isSavingUsername ? null : _updateUsername,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _usernameController.text = username ?? '';
                      setState(() => isEditingUsername = false);
                    },
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    username ?? 'No username',
                    style: const TextStyle(fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () {
                      setState(() => isEditingUsername = true);
                    },
                  ),
                ],
              ),

            const SizedBox(height: 4),

            Text(
              email ?? 'No email',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
