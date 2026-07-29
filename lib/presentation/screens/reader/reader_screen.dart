import 'package:flutter/material.dart';

class ReaderScreen extends StatelessWidget {
  final String bookId;
  
  const ReaderScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text('Book $bookId', style: const TextStyle(color: Colors.white)),
      ),
      body: const Center(
        child: Text(
          'Reader',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}