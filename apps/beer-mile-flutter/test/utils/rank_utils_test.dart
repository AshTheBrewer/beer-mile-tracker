// Tests for the competition-ranking utility used by the leaderboard screen.
//
// The leaderboard must assign shared ranks to runners with identical finish
// times, and skip the correct number of positions afterward.
//
// Example: two runners tied for 2nd → both show "2nd"; next runner shows "4th".

import 'package:flutter_test/flutter_test.dart';

import 'package:beer_mile/utils/rank_utils.dart';

void main() {
  group('computeRanks', () {
    // ── Basic cases ───────────────────────────────────────────────────────────

    test('returns empty list for empty input', () {
      expect(computeRanks([]), isEmpty);
    });

    test('single runner receives rank 1', () {
      expect(computeRanks([300000]), equals([1]));
    });

    test('all distinct times → sequential ranks', () {
      // 5 runners, all different times.
      expect(
        computeRanks([300000, 310000, 320000, 330000, 340000]),
        equals([1, 2, 3, 4, 5]),
      );
    });

    // ── Tie cases ─────────────────────────────────────────────────────────────

    test('two runners tied for 1st both receive rank 1; next runner is 3rd',
        () {
      // Ranks: 1, 1, 3
      expect(
        computeRanks([300000, 300000, 310000]),
        equals([1, 1, 3]),
      );
    });

    test('two runners tied for 2nd both receive rank 2; next runner is 4th',
        () {
      // Ranks: 1, 2, 2, 4  — the canonical Beer Mile tie scenario.
      expect(
        computeRanks([295000, 310000, 310000, 325000]),
        equals([1, 2, 2, 4]),
      );
    });

    test('three runners tied for 2nd all receive rank 2; next runner is 5th',
        () {
      // Ranks: 1, 2, 2, 2, 5
      expect(
        computeRanks([295000, 310000, 310000, 310000, 325000]),
        equals([1, 2, 2, 2, 5]),
      );
    });

    test('multiple separate tie groups are each ranked correctly', () {
      // Two runners tied at 1st (300 000), two tied at 3rd (310 000),
      // one alone at 5th (320 000).
      // Ranks: 1, 1, 3, 3, 5
      expect(
        computeRanks([300000, 300000, 310000, 310000, 320000]),
        equals([1, 1, 3, 3, 5]),
      );
    });

    test('all runners with the same time all receive rank 1', () {
      expect(
        computeRanks([300000, 300000, 300000]),
        equals([1, 1, 1]),
      );
    });

    // ── Edge values ───────────────────────────────────────────────────────────

    test('works correctly with a single entry per position (no ties)', () {
      expect(
        computeRanks([1, 2, 3]),
        equals([1, 2, 3]),
      );
    });

    test('handles a tie at the very last position', () {
      // Ranks: 1, 2, 3, 3
      expect(
        computeRanks([100, 200, 300, 300]),
        equals([1, 2, 3, 3]),
      );
    });
  });
}
