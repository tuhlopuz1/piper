import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piper/native/piper_events.dart';
import 'package:piper/widgets/mesh_graph_widget.dart';

void main() {
  testWidgets('MeshGraphWidget renders with topology snapshot', (tester) async {
    const topology = MeshTopology(
      localId: 'local',
      nodes: [
        MeshNode(
          id: 'local',
          name: 'Me',
          isSelf: true,
          isConnected: true,
          isRelay: false,
          hops: 1,
        ),
        MeshNode(
          id: 'peer-1',
          name: 'Bob',
          isSelf: false,
          isConnected: true,
          isRelay: false,
          hops: 1,
        ),
      ],
      edges: [
        MeshEdge(
          from: 'local',
          to: 'peer-1',
          kind: 'direct',
          hops: 1,
          isActive: true,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshGraphWidget(topology: topology),
        ),
      ),
    );

    expect(find.byType(MeshGraphWidget), findsOneWidget);
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
