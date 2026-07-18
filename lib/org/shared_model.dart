/// A model shared inside an organization / workspace.
class SharedModel {
  const SharedModel({
    required this.id,
    required this.name,
    this.quant,
    this.size,
    this.source = 'org',
    this.status = 'idle',
    this.accent = false,
  });

  final String id;
  final String name;
  final String? quant;
  final String? size;
  final String source;
  final String status;
  final bool accent;

  factory SharedModel.fromJson(Map<String, dynamic> j) => SharedModel(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        quant: j['quant']?.toString(),
        size: j['size']?.toString(),
        source: (j['source'] ?? 'org').toString(),
        status: (j['status'] ?? 'idle').toString(),
        accent: j['accent'] == true,
      );
}
