/// Maps Ottawa facility name fragments to place-listing slugs.
class FacilitySlugRegistry {
  static const Map<String, String> fragments = {
    'brewer pool': 'brewer-pool-and-arena',
    'champagne fitness': 'champagne-fitness-centre',
    'jack purcell': 'jack-purcell-community-centre',
    'lowertown': 'lowertown-community-centre-and-pool',
    'plant recreation': 'plant-recreation-centre',
    'bob macquarrie': 'bob-macquarrie-recreation-complex-orleans',
    'canterbury recreation': 'canterbury-recreation-complex',
    'canterbury wading': 'canterbury-wading-pool',
    'françois dupuis': 'francois-dupuis-recreation-centre',
    'francois dupuis': 'francois-dupuis-recreation-centre',
    'ray friel': 'ray-friel-recreation-complex',
    'splash wave': 'splash-wave-pool',
    'st. laurent': 'st-laurent-complex',
    'st-laurent': 'st-laurent-complex',
    'deborah anne kirwan': 'deborah-anne-kirwan-pool',
    'sawmill creek': 'sawmill-creek-community-centre-and-pool',
    'nepean sportsplex': 'nepean-sportsplex',
    'walter baker': 'walter-baker-sports-centre',
    'cardelrec': 'cardelrec-recreation-complex-goulbourn',
    'kanata leisure': 'kanata-leisure-centre-and-wave-pool',
    'minto recreation': 'minto-recreation-complex-barrhaven',
    'pinecrest': 'pinecrest-recreation-complex',
    'richcraft': 'richcraft-recreation-complex-kanata',
    'bearbrook': 'bearbrook-pool',
    'beaverbrook': 'beaverbrook-pool-kanata',
    'corkstown': 'corkstown-pool',
    'crestview': 'crestview-pool',
    'entrance pool': 'entrance-pool',
    'general burns': 'general-burns-pool',
    'genest': 'genest-pool',
    'glen cairn': 'glen-cairn-pool',
    'katimavik': 'katimavik-pool',
  };

  static String? slugForName(String name) {
    final lower = name.toLowerCase();
    for (final entry in fragments.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return _slugify(name);
  }

  static String _slugify(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
