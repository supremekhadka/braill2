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
  static const double toleranceFactor = 0.6;
  static const double wordGapMultiplier = 0.9;

  static List<BrailleLine> reconstruct(List<Detection> detections) {
    if (detections.isEmpty) return const [];

    final cells = _iqrFilter(detections.map(_toCell).toList());
    if (cells.isEmpty) return const [];

    final medianH = _median(cells.map((c) => c.height).toList());
    final medianW = _median(cells.map((c) => c.width).toList());
    final tol = medianH * toleranceFactor;

    cells.sort((a, b) => a.cy.compareTo(b.cy));
    final lineGroups = <_LineAccumulator>[];

    for (final cell in cells) {
      _LineAccumulator? bestLine;
      double bestDist = double.infinity;
      for (final line in lineGroups) {
        final dist = (cell.cy - line.predictY(cell.cx)).abs();
        if (dist < tol && dist < bestDist) {
          bestDist = dist;
          bestLine = line;
        }
      }
      (bestLine ?? (lineGroups..add(_LineAccumulator())).last).add(cell);
    }

    lineGroups.sort((a, b) => a.meanY.compareTo(b.meanY));
    return lineGroups.map((acc) {
      final sorted = acc.cells..sort((a, b) => a.cx.compareTo(b.cx));
      return BrailleLine(_segmentWords(sorted, medianW));
    }).toList();
  }

  static List<BrailleCell> _iqrFilter(List<BrailleCell> cells) {
    if (cells.length < 4) return cells;
    final widths = cells.map((c) => c.width).toList()..sort();
    final heights = cells.map((c) => c.height).toList()..sort();
    final (wLo, wHi) = _iqrBounds(widths);
    final (hLo, hHi) = _iqrBounds(heights);
    return cells
        .where(
          (c) =>
              c.width >= wLo &&
              c.width <= wHi &&
              c.height >= hLo &&
              c.height <= hHi,
        )
        .toList();
  }

  static (double, double) _iqrBounds(List<double> sorted) {
    final q1 = _percentile(sorted, 0.25);
    final q3 = _percentile(sorted, 0.75);
    final iqr = q3 - q1;
    return (q1 - 1.5 * iqr, q3 + 1.5 * iqr);
  }

  static double _percentile(List<double> sorted, double p) {
    final pos = p * (sorted.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  static List<BrailleWord> _segmentWords(
    List<BrailleCell> cells,
    double medianW,
  ) {
    if (cells.isEmpty) return const [];
    final threshold = medianW * wordGapMultiplier;
    final words = <BrailleWord>[];
    var current = <BrailleCell>[cells.first];
    for (int i = 1; i < cells.length; i++) {
      final gap =
          (cells[i].cx - cells[i].width / 2) -
          (cells[i - 1].cx + cells[i - 1].width / 2);
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
}

class _LineAccumulator {
  final List<BrailleCell> cells = [];
  double _n = 0, _sumX = 0, _sumY = 0, _sumXY = 0, _sumX2 = 0;

  double get meanY => _n > 0 ? _sumY / _n : 0;

  double predictY(double x) {
    if (_n < 2) return meanY;
    final denom = _n * _sumX2 - _sumX * _sumX;
    if (denom.abs() < 1e-12) return meanY;
    final slope = (_n * _sumXY - _sumX * _sumY) / denom;
    final intercept = (_sumY - slope * _sumX) / _n;
    return slope * x + intercept;
  }

  void add(BrailleCell cell) {
    cells.add(cell);
    _n++;
    _sumX += cell.cx;
    _sumY += cell.cy;
    _sumXY += cell.cx * cell.cy;
    _sumX2 += cell.cx * cell.cx;
  }
}
