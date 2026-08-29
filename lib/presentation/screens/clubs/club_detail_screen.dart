import 'package:flutter/material.dart';

class ClubDetailScreen extends StatelessWidget {
  final String clubId;
  
  const ClubDetailScreen({super.key, required this.clubId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Club $clubId', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      ),
      body: Center(
        child: Text(
          'Club Detail',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}