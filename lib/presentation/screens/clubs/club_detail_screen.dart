import 'package:flutter/material.dart';

class ClubDetailScreen extends StatelessWidget {
  final String clubId;
  
  const ClubDetailScreen({super.key, required this.clubId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text('Club $clubId', style: const TextStyle(color: Colors.white)),
      ),
      body: const Center(
        child: Text(
          'Club Detail',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}