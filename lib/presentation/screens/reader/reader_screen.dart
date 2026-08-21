import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class ReaderScreen extends StatelessWidget {
  final String bookId;
  
  const ReaderScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(
        backgroundColor: NOC.bg,
        title: Text('Book $bookId', style:  TextStyle(color: NOC.text)),
      ),
      body:  Center(
        child: Text(
          'Reader',
          style: TextStyle(color: NOC.text),
        ),
      ),
    );
  }
}