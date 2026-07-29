// lib/presentation/screens/feed/create_event_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../services/supabase_service.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isOnline = false;
  bool _isLoading = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00D4FF),
              surface: Color(0xFF1F1F1F),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00D4FF),
              surface: Color(0xFF1F1F1F),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _publishEvent() async {
    if (_titleController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      await SupabaseService().client.from('posts').insert({
        'type': 'event',
        'title': _titleController.text.trim(),
        'content': _descriptionController.text.trim(),
        'metadata': {
          'date': DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
          'time': _selectedTime.format(context),
          'location': _isOnline ? 'Online' : _locationController.text.trim(),
          'is_online': _isOnline,
          'datetime': dateTime.toIso8601String(),
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event posted!'),
            backgroundColor: Color(0xFFFF6A00),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Create Event'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishEvent,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Post', style: TextStyle(color: Color(0xFFFF6A00))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Event title',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _descriptionController,
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'What\'s happening?',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 32),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),

          // Date picker
          ListTile(
            leading: const Icon(Icons.calendar_today, color: Color(0xFF00D4FF)),
            title: const Text('Date', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
              style: const TextStyle(color: Color(0xFF888888)),
            ),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF888888)),
            onTap: _pickDate,
          ),

          // Time picker
          ListTile(
            leading: const Icon(Icons.access_time, color: Color(0xFF00D4FF)),
            title: const Text('Time', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _selectedTime.format(context),
              style: const TextStyle(color: Color(0xFF888888)),
            ),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF888888)),
            onTap: _pickTime,
          ),

          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),

          // Online toggle
          SwitchListTile(
            title: const Text('Online Event', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _isOnline ? 'Virtual meeting link will be shared' : 'In-person event',
              style: const TextStyle(color: Color(0xFF888888)),
            ),
            value: _isOnline,
            onChanged: (v) => setState(() => _isOnline = v),
            activeThumbColor: const Color(0xFF00D4FF),
          ),

          // Location (only if not online)
          if (!_isOnline)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextField(
                controller: _locationController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Venue address',
                  hintStyle: const TextStyle(color: Color(0xFF666666)),
                  prefixIcon: const Icon(Icons.location_on, color: Color(0xFF888888)),
                  filled: true,
                  fillColor: const Color(0xFF1F1F1F),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }
}