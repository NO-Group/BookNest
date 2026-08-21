import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class ClubsListScreen extends StatelessWidget {
  const ClubsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return  Scaffold(
      backgroundColor: NOC.bg,
      body: Center(
        child: Text(
          'Clubs',
          style: TextStyle(color: NOC.text),
        ),
      ),
    );
  }
}