import '../../../core/constants/app_constants.dart';

/// Maps Ottawa.ca raw activity labels to normalized swim types.
class SwimTypeNormalizer {
  static String normalize(String raw) {
    final lower = raw.toLowerCase().trim();

    if (_containsAny(lower, ['parent & tot', 'parent and tot', 'parent/tot'])) {
      return SwimCategories.parentTot;
    }
    if (_containsAny(lower, ['women', "women's", 'womens', 'female only'])) {
      return SwimCategories.womensSwim;
    }
    if (_containsAny(lower, ['preschool', 'pre-school', 'toddler'])) {
      return SwimCategories.preschoolSwim;
    }
    if (_containsAny(lower, ['teen swim', 'youth swim', 'teen only'])) {
      return SwimCategories.teenSwim;
    }
    if (_containsAny(lower, [
      'lane swim',
      'adult lane',
      'fitness swim',
      'length swim',
      'half lane',
    ])) {
      return SwimCategories.laneSwim;
    }
    if (_containsAny(lower, [
      'aquafit',
      'aqua fit',
      'aquafitness',
      'aqua-fit',
      'deep water aquafit',
      'deep-water aquafit',
    ])) {
      return SwimCategories.aquafit;
    }
    if (_containsAny(lower, [
      'aqua therapy',
      'aquatic therapy',
      'therapeutic',
      'therapy swim',
      'rehab swim',
      'rehabilitation swim',
      'sensory swim',
      'chronic pain',
      'pain management',
    ])) {
      return SwimCategories.therapeuticSwim;
    }
    if (_containsAny(lower, ['50+', '50 plus', 'fifty plus', 'senior swim'])) {
      return SwimCategories.adultSwim;
    }
    if (lower.contains('family')) {
      return SwimCategories.familySwim;
    }
    if (_containsAny(lower, ['adult swim', 'adults only swim', 'adult only'])) {
      return SwimCategories.adultSwim;
    }
    if (_containsAny(lower, [
      'public swim',
      'leisure swim',
      'recreation swim',
      'rec swim',
      'open swim',
      'general swim',
      'alternate needs swim',
      'accessibility swim',
      'accessible swim',
    ])) {
      return SwimCategories.generalSwim;
    }
    if (_containsAny(lower, ['wave swim', 'wave tank']) || lower == 'wave') {
      return SwimCategories.waveSwim;
    }
    if (lower.contains('swim')) {
      return SwimCategories.generalSwim;
    }

    return 'other';
  }

  static bool isSwimRow(String raw) {
    if (normalize(raw) != 'other') return true;
    final lower = raw.toLowerCase();
    return lower.contains('swim') ||
        lower.contains('aquafit') ||
        lower.contains('aqua fit') ||
        lower.contains('aqua therapy') ||
        lower.contains('aquatic') ||
        lower.contains('chronic pain') ||
        lower.contains('pain management') ||
        lower.contains('hot tub') ||
        lower.contains('wave') ||
        lower.contains('wading') ||
        lower.contains('splash');
  }

  static bool isDisplayable(String category) =>
      SwimCategories.all.contains(SwimCategories.normalizeStored(category));

  static bool _containsAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);

  /// Strips Ottawa.ca footnotes (e.g. "*Reservations required") from row labels.
  static String cleanRawActivityLabel(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[\u2018\u2019]'), "'");
    cleaned = cleaned.split(RegExp(r'[\r\n]+')).first;
    cleaned = cleaned.split('*').first;
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

String normalizeSwimCategory(String raw) => SwimTypeNormalizer.normalize(raw);

bool isSwimRow(String raw) => SwimTypeNormalizer.isSwimRow(raw);
