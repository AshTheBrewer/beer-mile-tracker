/// Rank computation utilities for the Beer Mile leaderboard.

/// Computes standard competition ranks ("1224" ranking) for a pre-sorted list
/// of elapsed times.
///
/// Two entries with identical [totalElapsedMs] values receive the same rank.
/// The next distinct time skips positions equal to the number of tied entries,
/// so three runners tied for 2nd are all shown "2nd" and the next runner is
/// shown "5th".
///
/// [elapsedMs] must already be sorted ascending (fastest first). Pass only the
/// times you want ranked; in-progress / unfinished entries should be handled
/// by the caller before passing values here.
///
/// Returns a list of 1-based ranks with the same length as [elapsedMs].
///
/// Example:
/// ```dart
/// computeRanks([300000, 310000, 310000, 320000])
/// // → [1, 2, 2, 4]
/// ```
List<int> computeRanks(List<int> elapsedMs) {
  if (elapsedMs.isEmpty) return [];

  final ranks = List<int>.filled(elapsedMs.length, 0);
  for (var i = 0; i < elapsedMs.length; i++) {
    if (i == 0 || elapsedMs[i] != elapsedMs[i - 1]) {
      // New distinct time: rank is 1-based position in the list.
      ranks[i] = i + 1;
    } else {
      // Same time as previous entry: share the same rank.
      ranks[i] = ranks[i - 1];
    }
  }
  return ranks;
}
