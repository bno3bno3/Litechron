import 'practice_score_item.dart';

enum PracticeFilter { all, aesthetic, other }

/// A successful empty response is also a cache. Totals remain owned by Scholar.
class PracticeDetails {
  final List<PracticeScoreItem> items;
  final DateTime? updatedAt;
  final bool complete;
  final String? error;

  const PracticeDetails({
    this.items = const [],
    this.updatedAt,
    this.complete = true,
    this.error,
  });

  bool get hasCache => updatedAt != null;

  PracticeDetails withError(String message) => PracticeDetails(
        items: items,
        updatedAt: updatedAt,
        complete: complete,
        error: message,
      );

  List<PracticeScoreItem> records(int category, PracticeFilter filter) {
    final result = items
        .where((item) =>
            !item.deleted &&
            item.categoryId == category &&
            (category != 1 ||
                filter == PracticeFilter.all ||
                (filter == PracticeFilter.aesthetic
                    ? item.isAesthetic
                    : item.hasQualityType && !item.isAesthetic)))
        .toList();
    result.sort((a, b) {
      final date = (b.activityStart ?? b.updatedAt ?? DateTime(1970))
          .compareTo(a.activityStart ?? a.updatedAt ?? DateTime(1970));
      return date == 0 ? b.id.compareTo(a.id) : date;
    });
    return result;
  }

  double? subtotal(PracticeFilter filter) {
    if (!hasCache || !complete) return null;
    final approved =
        items.where((item) => item.categoryId == 1 && item.countsTowardTotal);
    if (approved.any((item) => !item.hasQualityType)) return null;
    return approved
        .where((item) =>
            filter == PracticeFilter.all ||
            (filter == PracticeFilter.aesthetic
                ? item.isAesthetic
                : !item.isAesthetic))
        .fold<double>(0, (sum, item) => sum + item.score);
  }
}
