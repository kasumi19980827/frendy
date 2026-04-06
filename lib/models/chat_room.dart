class ChatRoom {
  final String id;
  final String title;
  final String ownerId;
  int currentMemberCount;

  ChatRoom({
    required this.id,
    required this.title,
    required this.ownerId,
    this.currentMemberCount = 1,
  });
}