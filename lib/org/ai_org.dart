/// An Erebrus AI organization / workspace.
class AiOrg {
  const AiOrg({
    required this.id,
    required this.name,
    this.slug,
    this.role = 'member',
    this.plan,
    this.memberCount,
    this.privateModelCount,
    this.pendingInviteCount,
  });

  final String id;
  final String name;
  final String? slug;
  final String role;
  final String? plan;
  final int? memberCount;
  final int? privateModelCount;
  final int? pendingInviteCount;

  factory AiOrg.fromJson(Map<String, dynamic> j) => AiOrg(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        slug: j['slug']?.toString(),
        role: (j['role'] ?? 'member').toString(),
        plan: j['plan']?.toString(),
        memberCount: j['member_count'] is int ? j['member_count'] as int : null,
        privateModelCount: j['private_model_count'] is int ? j['private_model_count'] as int : null,
        pendingInviteCount: j['pending_invite_count'] is int ? j['pending_invite_count'] as int : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (slug != null) 'slug': slug,
        'role': role,
        if (plan != null) 'plan': plan,
        if (memberCount != null) 'member_count': memberCount,
        if (privateModelCount != null) 'private_model_count': privateModelCount,
        if (pendingInviteCount != null) 'pending_invite_count': pendingInviteCount,
      };

  bool get isAdmin => role == 'admin' || role == 'owner';
}
