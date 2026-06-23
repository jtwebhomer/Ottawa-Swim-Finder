class Facility {
  const Facility({
    required this.id,
    required this.name,
    this.address,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.region,
    this.url,
    this.contentHash,
    this.lastUpdated,
    this.isFavorite = false,
    this.metadataJson,
  });

  final String id;
  final String name;
  final String? address;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final String? region;
  final String? url;
  final String? contentHash;
  final int? lastUpdated;
  final bool isFavorite;
  final String? metadataJson;

  Facility copyWith({
    bool? isFavorite,
    String? contentHash,
    int? lastUpdated,
  }) {
    return Facility(
      id: id,
      name: name,
      address: address,
      postalCode: postalCode,
      latitude: latitude,
      longitude: longitude,
      region: region,
      url: url,
      contentHash: contentHash ?? this.contentHash,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isFavorite: isFavorite ?? this.isFavorite,
      metadataJson: metadataJson,
    );
  }
}
