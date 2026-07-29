import 'package:flutter/material.dart';

class DMListScreen extends StatelessWidget {
  const DMListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0A),
      body: Center(
        child: Text(
          'DMs',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}