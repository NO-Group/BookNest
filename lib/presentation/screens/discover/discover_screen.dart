// lib/presentation/screens/discover/discover_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _communities = [];
  List<dynamic> _clubs = [];
  List<dynamic> _organizations = [];
  List<dynamic> _schools = [];
  List<dynamic> _filteredItems = [];
  bool _isLoading = true;
  String _activeFilter = 'All';
  bool _isPlusOpen = false;

  late AnimationController _plusController;
  late Animation<double> _plusRotation;

  final List<String> _filters = ['All', 'Clubs', 'Organizations', 'Schools', 'Communities'];

  final List<_CreateOption> _createOptions = const [
    _CreateOption(label: 'New Club', icon: Icons.menu_book, color: Color(0xFF00D4FF), route: '/create/club'),
    _CreateOption(label: 'New Organization', icon: Icons.business, color: Color(0xFFFF6A00), route: '/create/organization'),
    _CreateOption(label: 'New School', icon: Icons.school, color: Color(0xFF00D4FF), route: '/create/school'),
    _CreateOption(label: 'New Community', icon: Icons.account_tree, color: Color(0xFFFF6A00), route: '/create/community'),
  ];

  @override
  void initState() {
    super.initState();
    _plusController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _plusRotation = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _plusController, curve: Curves.easeOutBack),
    );
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final futures = await Future.wait([
        SupabaseService().client.from('communities').select('*, community_members(count)').order('created_at', ascending: false),
        SupabaseService().client.from('clubs').select('*, club_members(count)').eq('is_private', false).order('created_at', ascending: false),
        SupabaseService().client.from('organizations').select('*, organization_members(count)').eq('is_private', false).order('created_at', ascending: false),
        SupabaseService().client.from('schools').select('*, school_members(count)').eq('is_private', false).order('created_at', ascending: false),
      ]);

      setState(() {
        _communities = futures[0].map((c) => {...c, 'type': 'community'}).toList();
        _clubs = futures[1].map((c) => {...c, 'type': 'club'}).toList();
        _organizations = futures[2].map((c) => {...c, 'type': 'organization'}).toList();
        _schools = futures[3].map((c) => {...c, 'type': 'school'}).toList();
        _filteredItems = [..._communities, ..._clubs, ..._organizations, ..._schools];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterItems(String filter) {
    setState(() {
      _activeFilter = filter;
      switch (filter) {
        case 'All':
          _filteredItems = [..._communities, ..._clubs, ..._organizations, ..._schools];
          break;
        case 'Clubs':
          _filteredItems = _clubs;
          break;
        case 'Organizations':
          _filteredItems = _organizations;
          break;
        case 'Schools':
          _filteredItems = _schools;
          break;
        case 'Communities':
          _filteredItems = _communities;
          break;
      }
    });
  }

  void _togglePlus() {
    setState(() => _isPlusOpen = !_isPlusOpen);
    if (_isPlusOpen) {
      _plusController.forward();
    } else {
      _plusController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Discover',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: _togglePlus,
                        child: AnimatedBuilder(
                          animation: _plusRotation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _plusRotation.value * 3.14159 * 2,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F1F1F),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF222222)),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Color(0xFF00D4FF),
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search communities, clubs, schools...',
                      hintStyle: const TextStyle(color: Color(0xFF666666)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF666666)),
                      filled: true,
                      fillColor: const Color(0xFF1F1F1F),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Filter tabs
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filters.length,
                    itemBuilder: (context, index) {
                      final filter = _filters[index];
                      final isActive = _activeFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _filterItems(filter),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF00D4FF)
                                  : const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(20),
                              border: isActive
                                  ? null
                                  : Border.all(color: const Color(0xFF222222)),
                            ),
                            child: Text(
                              filter,
                              style: TextStyle(
                                color: isActive ? const Color(0xFF0A0A0A) : Colors.white,
                                fontSize: 13,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Items list
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
                        )
                      : _filteredItems.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              itemCount: _filteredItems.length,
                              itemBuilder: (context, index) {
                                return _DiscoverCard(item: _filteredItems[index]);
                              },
                            ),
                ),
              ],
            ),
          ),

          // Plus button vertical stack
          Positioned(
            right: 20,
            top: 60,
            child: AnimatedOpacity(
              opacity: _isPlusOpen ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                height: _isPlusOpen ? (_createOptions.length * 56.0) : 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _createOptions.map((option) {
                    return GestureDetector(
                      onTap: () {
                        _togglePlus();
                        context.push(option.route);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF222222)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(option.icon, color: option.color, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              option.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore_outlined, size: 64, color: Color(0xFF444444)),
          SizedBox(height: 16),
          Text(
            'Nothing here yet',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            'Be the first to create something',
            style: TextStyle(color: Color(0xFF888888), fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _plusController.dispose();
    super.dispose();
  }
}

class _CreateOption {
  final String label;
  final IconData icon;
  final Color color;
  final String route;

  const _CreateOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
  });
}

class _DiscoverCard extends StatelessWidget {
  final dynamic item;

  const _DiscoverCard({required this.item});

  Color get _typeColor {
    switch (item['type']) {
      case 'community':
        return const Color(0xFF00D4FF);
      case 'club':
        return const Color(0xFFFF6A00);
      case 'organization':
        return const Color(0xFF00D4FF);
      case 'school':
        return const Color(0xFFFF6A00);
      default:
        return const Color(0xFF888888);
    }
  }

  String get _typeLabel {
    switch (item['type']) {
      case 'community':
        return 'COMMUNITY';
      case 'club':
        return 'CLUB';
      case 'organization':
        return 'ORGANIZATION';
      case 'school':
        return 'SCHOOL';
      default:
        return '';
    }
  }

  IconData get _typeIcon {
    switch (item['type']) {
      case 'community':
        return Icons.account_tree;
      case 'club':
        return Icons.menu_book;
      case 'organization':
        return Icons.business;
      case 'school':
        return Icons.school;
      default:
        return Icons.group;
    }
  }

  int get _memberCount {
    final key = '${item['type']}_members';
    return item[key]?[0]?['count'] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigateToDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF222222)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                image: item['cover_image_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(item['cover_image_url']),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: item['cover_image_url'] == null
                  ? Center(
                      child: Icon(
                        _typeIcon,
                        size: 40,
                        color: _typeColor.withValues(alpha: 0.3),
                      ),
                    )
                  : null,
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _typeLabel,
                          style: TextStyle(
                            color: _typeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (item['is_verified'] == true) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.verified, color: Color(0xFF00D4FF), size: 16),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item['name'] ?? 'Unnamed',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['description'] ?? 'No description',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.people, size: 14, color: Color(0xFF888888)),
                      const SizedBox(width: 6),
                      Text(
                        '$_memberCount members',
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                      if (item['type'] == 'school' && item['location'] != null) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.location_on, size: 14, color: Color(0xFF888888)),
                        const SizedBox(width: 6),
                        Text(
                          item['location'],
                          style: const TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    switch (item['type']) {
      case 'community':
        context.push('/community/${item['id']}');
        break;
      case 'club':
        context.push('/club/${item['id']}');
        break;
      case 'organization':
        context.push('/organization/${item['id']}');
        break;
      case 'school':
        context.push('/school/${item['id']}');
        break;
    }
  }
}