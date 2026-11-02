import 'dart:ui';

import 'package:appmistakemap/ai/analysis_models.dart';
import 'package:appmistakemap/ai/force_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const box = Size(120, 96);

  List<GraphNode> nodes(int concepts) => [
    GraphNode('subject:math', 'Matemática', 'Matéria', {'a0'}),
    for (var i = 0; i < concepts; i++)
      GraphNode('concept:$i', 'Conceito $i', 'Conceito', {'a$i'}),
    GraphNode('type:sinal', 'Sinal', 'Tipo de erro', {'a0'}),
    GraphNode('subject:bio', 'Biologia', 'Matéria', {'b0'}),
    GraphNode('concept:mendel', 'Mendel', 'Conceito', {'b0'}),
  ];

  List<GraphEdge> edges(int concepts) => [
    for (var i = 0; i < concepts; i++) ...[
      GraphEdge('subject:math', 'concept:$i', {'a$i'}),
      GraphEdge('concept:$i', 'type:sinal', {'a$i'}),
    ],
    GraphEdge('subject:bio', 'concept:mendel', {'b0'}),
  ];

  test('é determinístico', () {
    final a = computeForceLayout(nodes(8), edges(8), nodeBox: box);
    final b = computeForceLayout(nodes(8), edges(8), nodeBox: box);
    expect(a.canvasSize, b.canvasSize);
    for (final id in a.points.keys) {
      expect(a.points[id], b.points[id]);
    }
  });

  test('nenhum rótulo se sobrepõe e todos cabem no quadro', () {
    final layout = computeForceLayout(nodes(20), edges(20), nodeBox: box);
    final points = layout.points.values.toList();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      expect(p.dx - box.width / 2, greaterThanOrEqualTo(0));
      expect(p.dy - box.height / 2, greaterThanOrEqualTo(0));
      expect(p.dx + box.width / 2, lessThanOrEqualTo(layout.canvasSize));
      expect(p.dy + box.height / 2, lessThanOrEqualTo(layout.canvasSize));
      for (var j = i + 1; j < points.length; j++) {
        final overlap =
            (p.dx - points[j].dx).abs() < box.width &&
            (p.dy - points[j].dy).abs() < box.height;
        expect(overlap, isFalse, reason: 'nós $i e $j se cruzam');
      }
    }
  });

  test('vizinhos ficam mais perto que nós sem ligação', () {
    final layout = computeForceLayout(nodes(6), edges(6), nodeBox: box);
    final p = layout.points;
    final linked = (p['subject:bio']! - p['concept:mendel']!).distance;
    final unlinked = (p['concept:mendel']! - p['type:sinal']!).distance;
    expect(linked, lessThan(unlinked));
  });

  test('grafo vazio devolve quadro mínimo', () {
    final layout = computeForceLayout(const [], const []);
    expect(layout.points, isEmpty);
    expect(layout.canvasSize, 440);
  });
}
