import 'package:blog_mobile/utils/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => RegisterScreenState();
}

class RegisterScreenState extends State<RegisterScreen> {
    final _nameController = TextEditingController();
    final _emailController = TextEditingController();
    final _passwordController = TextEditingController();
    final _confirmPasswordController = TextEditingController();

    bool isLoading = false;

    @override
    void dispose() {
        _emailController.dispose();
        _passwordController.dispose();
        _confirmPasswordController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            body: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        colors: [
                            const Color.fromRGBO(49, 27, 146, 1),
                            const Color.fromRGBO(69, 39, 160, 1),
                            const Color.fromRGBO(126, 87, 194, 1)
                        ]
                    ),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                        SizedBox(height: 80),
                        Padding(
                            padding: EdgeInsetsGeometry.all(20),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                    Text(
                                        'Register',
                                        style: TextStyle(
                                            fontSize: 40,
                                            color: Colors.white
                                        ),
                                    ),
                                    Text(
                                        'Come. Join Us Now.',
                                        style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.white
                                        ),
                                    )
                                ],
                            )
                        ),
                        Expanded(
                            child: Container(
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(40),
                                        topRight: Radius.circular(40)
                                    )
                                ),
                                child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Column(
                                        children: [
                                            SizedBox(height: 40),
                                            Container(
                                                padding: EdgeInsets.all(20),
                                                decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(15),
                                                    boxShadow: [BoxShadow(
                                                        color: Color.fromRGBO(77, 16, 146, 0.298),
                                                        blurRadius: 20,
                                                        offset: Offset(0, 10)
                                                    )]
                                                ),
                                                child: Column(
                                                    children: [
                                                        Container(
                                                            padding: EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                                border: Border(bottom: BorderSide(color: const Color.fromRGBO(238, 238, 238, 1)))
                                                            ),
                                                            child: TextField(
                                                                controller: _nameController,
                                                                decoration: InputDecoration(
                                                                    hintText: "Name",
                                                                    hintStyle: TextStyle(color: Colors.grey),
                                                                    border: InputBorder.none
                                                                ),
                                                            ),
                                                        ),
                                                        Container(
                                                            padding: EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                                border: Border(bottom: BorderSide(color: const Color.fromRGBO(238, 238, 238, 1)))
                                                            ),
                                                            child: TextField(
                                                                controller: _emailController,
                                                                decoration: InputDecoration(
                                                                    hintText: "Email",
                                                                    hintStyle: TextStyle(color: Colors.grey),
                                                                    border: InputBorder.none
                                                                ),
                                                            ),
                                                        ),
                                                        Container(
                                                            padding: EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                                border: Border(bottom: BorderSide(color: const Color.fromRGBO(238, 238, 238, 1)))
                                                            ),
                                                            child: TextField(
                                                                controller: _passwordController,
                                                                obscureText: true,
                                                                decoration: InputDecoration(
                                                                    hintText: "Password",
                                                                    hintStyle: TextStyle(color: Colors.grey),
                                                                    border: InputBorder.none
                                                                ),
                                                            ),
                                                        ),
                                                        Container(
                                                            padding: EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                                border: Border(bottom: BorderSide(color: const Color.fromRGBO(238, 238, 238, 1)))
                                                            ),
                                                            child: TextField(
                                                                controller: _confirmPasswordController,
                                                                obscureText: true,
                                                                decoration: InputDecoration(
                                                                    hintText: "Confirm Password",
                                                                    hintStyle: TextStyle(color: Colors.grey),
                                                                    border: InputBorder.none
                                                                ),
                                                            ),
                                                        ),
                                                    ],
                                                ),
                                            ),
                                            SizedBox(height: 25),
                                            ElevatedButton(
                                                onPressed: isLoading ? null : _register,
                                                style: ElevatedButton.styleFrom(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 120,
                                                    vertical: 15
                                                ),
                                                backgroundColor: Colors.deepPurple
                                                ),
                                                child: isLoading
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                    ),
                                                )
                                                : const Text(
                                                'Register',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                ),
                                                )
                                            ),
                                            TextButton(
                                                onPressed: () {
                                                    Navigator.pop(context);
                                                }, 
                                                style: TextButton.styleFrom(
                                                overlayColor: Colors.transparent
                                                ),
                                                child: const Text(
                                                'Already have an account? Login',
                                                style: TextStyle(
                                                    color: Colors.grey
                                                ),
                                                )
                                            )
                                        ],
                                    ),
                                ),
                            )
                        )
                    ],
                )
            )
        );
    }

    void _register() async {
      if (_passwordController.text != _confirmPasswordController.text) {
        UiHelpers.showError(context, 'Passwords do not match');
        return;
      }

      if (_nameController.text.trim().isEmpty) {
        UiHelpers.showError(context, 'Name is required');
        return;
      }

      setState(() => isLoading = true);

      try {
        final response = await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        final user = response.user;

        if (user != null) {
          await Supabase.instance.client
            .from('profiles')
            .update({'username': _nameController.text.trim()})
            .eq('id', user.id);
        } else {
          throw 'Registration failed';
        }

        if (!mounted) return;

        UiHelpers.showSuccess(
          context,
          'Account created! Please verify your email and login.',
        );

        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        UiHelpers.showError(context, e.toString());
      } finally {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    }

}