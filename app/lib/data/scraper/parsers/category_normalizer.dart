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
    if (_containsAny(lower, ['preschool', 'pre-school'])) {
      return SwimCategories.preschoolSwim;
    }
    if (_containsAny(lower, [
      'lane swim',
      'adult lane',
      'fitness swim',
      'length swim',
    ])) {
      return SwimCategories.laneSwim;
    }
    if (_containsAny(lower, ['aquafit', 'aqua fit', 'aquafitness', 'aqua-fit'])) {
      return SwimCategories.aquafit;
    }
    if (_containsAny(lower, [
      'aqua therapy',
      'aquatic therapy',
      'therapeutic',
      'therapy swim',
    ])) {
      return SwimCategories.therapeuticSwim;
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
        lower.contains('hot tub') ||
        lower.contains('wave');
  }

  static bool isDisplayable(String category) =>
      SwimCategories.all.contains(SwimCategories.normalizeStored(category));

  static bool _containsAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);
}

String normalizeSwimCategory(String raw) => SwimTypeNormalizer.normalize(raw);

bool isSwimRow(String raw) => SwimTypeNormalizer.isSwimRow(raw);
