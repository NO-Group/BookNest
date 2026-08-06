import 'package:flutter/material.dart';

import '../../../config/theme.dart';

enum BookNestChatType {
  dm,
  club,
  organization,
  school,
  communityAnnouncement,
  nexus,
}

BookNestChatType chatTypeFromString(String? value) {
  switch (value) {
    case 'club': return BookNestChatType.club;
    case 'organization': return BookNestChatType.organization;
    case 'school': return BookNestChatType.school;
    case 'community_announcement': return BookNestChatType.communityAnnouncement;
    case 'nexus': return BookNestChatType.nexus;
    default: return BookNestChatType.dm;
  }
}

extension ChatTypeDetails on BookNestChatType {
  String get databaseValue {
    switch (this) {
      case BookNestChatType.communityAnnouncement: return 'community_announcement';
      default: return name;
    }
  }

  String get label {
    switch (this) {
      case BookNestChatType.dm: return 'Direct message';
      case BookNestChatType.club: return 'Club chat';
      case BookNestChatType.organization: return 'Organization';
      case BookNestChatType.school: return 'School channel';
      case BookNestChatType.communityAnnouncement: return 'Community announcements';
      case BookNestChatType.nexus: return 'The Nexus';
    }
  }

  IconData get icon {
    switch (this) {
      case BookNestChatType.dm: return Icons.person_outline;
      case BookNestChatType.club: return Icons.menu_book_outlined;
      case BookNestChatType.organization: return Icons.account_balance_outlined;
      case BookNestChatType.school: return Icons.school_outlined;
      case BookNestChatType.communityAnnouncement: return Icons.campaign_outlined;
      case BookNestChatType.nexus: return Icons.public;
    }
  }

  Color get color {
    switch (this) {
      case BookNestChatType.nexus: return BookNestColors.yellow;
      case BookNestChatType.communityAnnouncement: return BookNestColors.orange;
      case BookNestChatType.organization: return BookNestColors.cyan;
      case BookNestChatType.school: return const Color(0xFF9B8CFF);
      case BookNestChatType.club: return const Color(0xFF65D68A);
      case BookNestChatType.dm: return BookNestColors.cyan;
    }
  }

  bool get isBroadcast => this == BookNestChatType.nexus || this == BookNestChatType.communityAnnouncement;
}

class BookNestChat {
  final String id;
  final BookNestChatType type;
  final String title;
  final String? description;
  final String? avatarUrl;
  final bool canPost;
  final bool canLeave;
  final String? lastMessage;
  final DateTime? updatedAt;

  const BookNestChat({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.avatarUrl,
    required this.canPost,
    required this.canLeave,
    this.lastMessage,
    this.updatedAt,
  });

  factory BookNestChat.fromMap(Map<String, dynamic> map, {bool canPost = true}) {
    final type = chatTypeFromString(map['chat_type'] as String?);
    return BookNestChat(
      id: map['id'].toString(),
      type: type,
      title: (map['title'] as String?)?.trim().isNotEmpty == true ? map['title'] as String : type.label,
      description: map['description'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      // The database decides whether this participant may post. This is
      // intentionally not derived only from chat type: the official BookNest
      // account must be able to publish into Nexus while regular members may
      // only react and vote.
      canPost: canPost,
      canLeave: type != BookNestChatType.nexus,
      lastMessage: map['last_message'] as String?,
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }
}

class ChatMessage {
  final String id;
  final String chatId;
  final String? senderId;
  final String kind;
  final String? body;
  final Map<String, dynamic> metadata;
  final String? replyTo;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isMine;
  final Map<String, int> reactions;

  const ChatMessage({
    required this.id,
    required this.chatId,
    this.senderId,
    required this.kind,
    this.body,
    this.metadata = const {},
    this.replyTo,
    required this.createdAt,
    this.editedAt,
    required this.isMine,
    this.reactions = const {},
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    final rawReactions = map['reactions'];
    final reactions = <String, int>{};
    if (rawReactions is List) {
      for (final reaction in rawReactions) {
        final emoji = reaction['emoji']?.toString();
        if (emoji != null) reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      }
    }
    return ChatMessage(
      id: map['id'].toString(),
      chatId: map['chat_id'].toString(),
      senderId: map['sender_id']?.toString(),
      kind: (map['message_type'] ?? 'text').toString(),
      body: map['body'] as String?,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? const {}),
      replyTo: map['reply_to']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      editedAt: DateTime.tryParse(map['edited_at']?.toString() ?? ''),
      isMine: map['sender_id']?.toString() == currentUserId,
      reactions: reactions,
    );
  }
}
