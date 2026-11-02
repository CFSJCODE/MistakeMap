import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'analysis_models.dart';

/// Posições calculadas para o grafo de erros.
class ForceLayout {
  /// Centro de cada nó, em coordenadas do quadro.
  final Map<String, Offset> points;

  /// Lado do quadro quadrado que contém todos os nós com margem.
  final double canvasSize;

  const ForceLayout(this.points, this.canvasSize);
}

/// Layout de força dirigida (Fruchterman–Reingold) para o grafo de erros.
///
/// Os nós se repelem como cargas (k²/d) e cada aresta puxa como mola
/// (d²/k), mais forte quanto mais tentativas a sustentam. Uma gravidade
/// leve segura componentes soltos perto do centro. O resultado é
/// determinístico: parte dos anéis por tipo de nó (sem sorteio) e roda um
/// número fixo de passos com resfriamento linear, então o mesmo mapa sempre
/// gera o mesmo desenho. No fim, uma passada de colisão afasta caixas que
/// ainda se sobrepõem, já que cada nó ocupa um rótulo de [nodeBox].
ForceLayout computeForceLayout(
  List<GraphNode> nodes,
  List<GraphEdge> edges, {
  Size nodeBox = const Size(120, 96),
  double minCanvas = 440,
  int iterations = 300,
}) {
  if (nodes.isEmpty) return ForceLayout(const {}, minCanvas);

  final ids = [for (final n in nodes) n.id];
  final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final n = ids.length;

  // Distância ideal entre vizinhos: um pouco mais que a caixa do rótulo.
  final k = math.max(nodeBox.width, nodeBox.height) * 1.25;

  // Semente determinística: anéis Matéria → Conceito → Tipo de erro.
  final groups = ['Matéria', 'Conceito', 'Tipo de erro']
      .map(
        (kind) =>
            nodes.where((node) => node.kind == kind).toList()
              ..sort((a, b) => a.label.compareTo(b.label)),
      )
      .toList();
  final others = nodes
      .where(
        (node) => !['Matéria', 'Conceito', 'Tipo de erro'].contains(node.kind),
      )
      .toList();
  if (others.isNotEmpty) groups.last.addAll(others);
  final seedRadius = k * math.max(1.0, math.sqrt(n) / 2);
  final pos = List<Offset>.filled(n, Offset.zero);
  for (var ring = 0; ring < groups.length; ring++) {
    final group = groups[ring];
    final radius = seedRadius * [.4, .75, 1.0][ring];
    for (var i = 0; i < group.length; i++) {
      final angle =
          -math.pi / 2 + 2 * math.pi * (i + ring * .18) / group.length;
      pos[index[group[i].id]!] = Offset(
        radius * math.cos(angle),
        radius * math.sin(angle),
      );
    }
  }

  final springs = <(int, int, double)>[
    for (final edge in edges)
      if (index[edge.from] != null &&
          index[edge.to] != null &&
          edge.from != edge.to)
        (
          index[edge.from]!,
          index[edge.to]!,
          1 + math.log(1 + edge.attemptIds.length) / 2,
        ),
  ];

  var temperature = seedRadius / 2;
  final cooling = temperature / (iterations + 1);
  final disp = List<Offset>.filled(n, Offset.zero);
  for (var step = 0; step < iterations; step++) {
    for (var i = 0; i < n; i++) {
      disp[i] = Offset.zero;
    }
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var delta = pos[i] - pos[j];
        var d = delta.distance;
        if (d < .01) {
          // Nós coincidentes: separa numa direção fixa pelo índice.
          delta = Offset(
            math.cos(i + j.toDouble()),
            math.sin(i + j.toDouble()),
          );
          d = .01;
        }
        final push = delta / d * (k * k / d);
        disp[i] += push;
        disp[j] -= push;
      }
    }
    for (final (a, b, weight) in springs) {
      final delta = pos[a] - pos[b];
      final d = math.max(delta.distance, .01);
      final pull = delta / d * (d * d / k * weight);
      disp[a] -= pull;
      disp[b] += pull;
    }
    for (var i = 0; i < n; i++) {
      // Gravidade leve para componentes desconexos não fugirem do quadro.
      disp[i] -= pos[i] * .05;
      final d = disp[i].distance;
      if (d > 0) pos[i] += disp[i] / d * math.min(d, temperature);
    }
    temperature -= cooling;
  }

  _resolveOverlaps(pos, nodeBox);

  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in pos) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  final margin = math.max(nodeBox.width, nodeBox.height) * .75;
  final canvasSize = math.max(
    minCanvas,
    math.max(maxX - minX, maxY - minY) + 2 * margin,
  );
  final shift = Offset(
    (canvasSize - (maxX - minX)) / 2 - minX,
    (canvasSize - (maxY - minY)) / 2 - minY,
  );
  return ForceLayout({
    for (var i = 0; i < n; i++) ids[i]: pos[i] + shift,
  }, canvasSize);
}

/// Afasta pares cujas caixas de rótulo ainda se cruzam, pelo eixo de menor
/// sobreposição, até não sobrar cruzamento (ou acabar o limite de passadas).
void _resolveOverlaps(List<Offset> pos, Size box) {
  final w = box.width + 8;
  final h = box.height + 8;
  for (var pass = 0; pass < 200; pass++) {
    var moved = false;
    for (var i = 0; i < pos.length; i++) {
      for (var j = i + 1; j < pos.length; j++) {
        final dx = pos[j].dx - pos[i].dx;
        final dy = pos[j].dy - pos[i].dy;
        final ox = w - dx.abs();
        final oy = h - dy.abs();
        if (ox <= 0 || oy <= 0) continue;
        moved = true;
        if (ox < oy) {
          final s = (dx >= 0 ? 1 : -1) * ox / 2;
          pos[i] = pos[i].translate(-s, 0);
          pos[j] = pos[j].translate(s, 0);
        } else {
          final s = (dy >= 0 ? 1 : -1) * oy / 2;
          pos[i] = pos[i].translate(0, -s);
          pos[j] = pos[j].translate(0, s);
        }
      }
    }
    if (!moved) return;
  }
}
