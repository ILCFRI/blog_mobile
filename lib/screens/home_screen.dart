import 'package:flutter/material.dart';
import 'package:blog_mobile/screens/feed_screen.dart';
import 'package:blog_mobile/screens/create_blog_screen.dart';
import 'package:blog_mobile/screens/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // 🔑 Key to access FeedScreen methods
  final GlobalKey<FeedScreenState> _feedKey =
      GlobalKey<FeedScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      FeedScreen(key: _feedKey),
      const SizedBox(), // placeholder (Create handled via modal)
      ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) async {
          // ➕ CREATE BLOG
          if (index == 1) {
            final created = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) {
                return SizedBox(
                  height: MediaQuery.of(context).size.height * 0.9,
                  child: const CreateBlogScreen(),
                );
              },
            );

            // 🔄 Refresh feed if post was created
            if (created == true) {
              setState(() => _currentIndex = 0);
              _feedKey.currentState?.refresh();
            }
            return;
          }

          setState(() => _currentIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Create Blog',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
