import 'dart:math';

import '../services/tflite_service.dart';

class BrailleCell {
  final Detection detection;
  final double cx, cy, width, height;

  const BrailleCell({
    required this.detection,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
  });
}

class BrailleWord {
  final List<BrailleCell> cells;
  const BrailleWord(this.cells);
}

class BrailleLine {
  final List<BrailleWord> words;
  const BrailleLine(this.words);
  List<BrailleCell> get allCells => words.expand((w) => w.cells).toList();
}

class LineReconstructor {
  static const double _tolFactor = 0.5;
  static const double _wordFactor = 1.5;

  static List<BrailleLine> reconstruct(List<Detection> detections) {
    if (detections.isEmpty) return const [];

    final cells = detections.map(_toCell).toList();

    final filtered = _filterOutliers(cells);
    if (filtered.isEmpty) return const [];

    final medianH = _median(filtered.map((c) => c.height).toList());
    final medianW = _median(filtered.map((c) => c.width).toList());
    final tol = medianH * _tolFactor;

    filtered.sort((a, b) => a.cy.compareTo(b.cy));

    final bands = <({double cy, List<BrailleCell> cells})>[];
    for (final cell in filtered) {
      final match = bands
          .cast<({double cy, List<BrailleCell> cells})?>()
          .firstWhere((b) => (cell.cy - b!.cy).abs() < tol, orElse: () => null);
      if (match != null) {
        match.cells.add(cell);
        final band = bands.firstWhere((b) => b.cells == match.cells);
        final idx = bands.indexOf(band);
        final newCy =
            band.cells.map((c) => c.cy).reduce((a, b) => a + b) /
            band.cells.length;
        bands[idx] = (cy: newCy, cells: band.cells);
      } else {
        bands.add((cy: cell.cy, cells: [cell]));
      }
    }

    bands.sort((a, b) => a.cy.compareTo(b.cy));

    return bands.map((band) {
      band.cells.sort((a, b) => a.cx.compareTo(b.cx));
      return BrailleLine(_segmentWords(band.cells, medianW));
    }).toList();
  }

  static List<BrailleCell> _filterOutliers(List<BrailleCell> cells) {
    if (cells.length < 4) return cells;
    final areas = (cells.map((c) => c.width * c.height).toList())..sort();
    final q1 = _percentile(areas, 0.25);
    final q3 = _percentile(areas, 0.75);
    final iqr = q3 - q1;
    final lo = q1 - 1.5 * iqr;
    final hi = q3 + 1.5 * iqr;
    return cells.where((c) {
      final a = c.width * c.height;
      return a >= lo && a <= hi;
    }).toList();
  }

  static List<BrailleWord> _segmentWords(
    List<BrailleCell> cells,
    double medianW,
  ) {
    if (cells.isEmpty) return const [];
    final threshold = medianW * _wordFactor;
    final words = <BrailleWord>[];
    var current = <BrailleCell>[cells.first];
    for (int i = 1; i < cells.length; i++) {
      final gap =
          cells[i].cx -
          cells[i - 1].cx -
          cells[i - 1].width / 2 -
          cells[i].width / 2;
      if (gap > threshold) {
        words.add(BrailleWord(List.unmodifiable(current)));
        current = [];
      }
      current.add(cells[i]);
    }
    words.add(BrailleWord(List.unmodifiable(current)));
    return List.unmodifiable(words);
  }

  static BrailleCell _toCell(Detection d) => BrailleCell(
    detection: d,
    cx: (d.x1 + d.x2) / 2,
    cy: (d.y1 + d.y2) / 2,
    width: d.x2 - d.x1,
    height: d.y2 - d.y1,
  );

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final s = List<double>.from(values)..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static double _percentile(List<double> sorted, double p) {
    final pos = p * (sorted.length - 1);
    final lo = pos.floor(), hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }
}
