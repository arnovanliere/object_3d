library object_3d;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' as vmath;
import 'package:vector_math/vector_math.dart' show Vector3;

class Object3D extends StatefulWidget {
  const Object3D({
    super.key,
    required this.size,
    this.color = Colors.white,
    this.object,
    this.path,
    this.swipeCoef = 0.1,
    this.dampCoef = 0.92,
    this.maxSpeed = 10.0,
    this.reversePitch = true,
    this.reverseYaw = false,
  })  : assert(
          object != null || path != null,
          'You must provide an object or a path',
        ),
        assert(
          object == null || path == null,
          'You must provide an object or a path, not both',
        );

  final Size size;
  final String? path;
  final String? object;
  final Color color;
  final double swipeCoef; // pan delta intensity
  final double dampCoef; // psuedo-friction 0.001-0.999
  final double maxSpeed; // in rots per 16 ms
  final bool reversePitch; // if true, rotation direction is flipped for pitch
  final bool reverseYaw; // if true, rotation direction is flipped for yaw

  @override
  State<Object3D> createState() => _Object3DState();
}

class _Object3DState extends State<Object3D> {
  double _pitch = 15.0, _yaw = 45.0;
  double? _previousX, _previousY;
  double _deltaX = 0.0, _deltaY = 0.0;
  List<Vector3> vertices = <vmath.Vector3>[];
  List<List<int>> faces = <List<int>>[];
  late Timer _updateTimer;

  @override
  void initState() {
    if (widget.path != null) {
      // Load the object file from assets
      rootBundle.loadString(widget.path!).then(_parseObj);
    } else if (widget.object != null) {
      // Load the object from a string
      _parseObj(widget.object!);
    }

    assert(
      widget.swipeCoef > 0,
      'Parameter swipeCoef must be a positive, non-zero real number.',
    );
    assert(
      widget.dampCoef >= 0.001 && widget.dampCoef <= 0.999,
      'Parameter dampCoef must be in the range [0.001, 0.999].',
    );
    assert(
      widget.maxSpeed > 0,
      'Parameter maxSpeed must be positive, non-zero real number.',
    );

    _updateTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      setState(() {
        final adx = _deltaX.abs();
        final ady = _deltaY.abs();
        final sx = _deltaX < 0 ? -1 : 1;
        final sy = _deltaY < 0 ? -1 : 1;

        _deltaX = math.min(widget.maxSpeed, adx) * sx * widget.dampCoef;
        _deltaY = math.min(widget.maxSpeed, ady) * sy * widget.dampCoef;

        _yaw = _yaw - (_deltaX * (widget.reversePitch ? -1 : 1));
        _pitch = _pitch - (_deltaY * (widget.reverseYaw ? -1 : 1));
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _updateTimer.cancel();
  }

  /// Parse the object file.
  void _parseObj(String obj) {
    final vertices = <vmath.Vector3>[];
    final faces = <List<int>>[];
    final lines = obj.split('\n');
    for (var line in lines) {
      const space = ' ';
      line = line.replaceAll(RegExp(r'\s+'), space);

      // Split into tokens and drop empty tokens
      final chars = line
          .split(space)
          .where((v) => v.isNotEmpty)
          .toList(growable: false);

      if (chars.isEmpty) continue;

      if (chars[0] == 'v') {
        vertices.add(
          Vector3(
            double.parse(chars[1]),
            double.parse(chars[2]),
            double.parse(chars[3]),
          ),
        );
      } else if (chars[0] == 'f') {
        final face = <int>[];
        for (var i = 1; i < chars.length; i++) {
          face.add(int.parse(chars[i].split('/')[0]));
        }
        faces.add(face);
      }
    }
    setState(() {
      this.vertices = vertices;
      this.faces = faces;
    });
  }

  /// Update the angle of rotation based on the change in position.
  void _handlePanDelta(DragUpdateDetails data) {
    if (_previousY != null) {
      _deltaY += widget.swipeCoef * (_previousY! - data.globalPosition.dy);
    }
    _previousY = data.globalPosition.dy;

    if (_previousX != null) {
      _deltaX += widget.swipeCoef * (_previousX! - data.globalPosition.dx);
    }
    _previousX = data.globalPosition.dx;
  }

  // invalidates _previousX and _previousY
  void _handlePanEnd(DragEndDetails _) {
    _previousX = null;
    _previousY = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: _handlePanDelta,
      onPanEnd: _handlePanEnd,
      child: CustomPaint(
        size: widget.size,
        painter: _ObjectPainter(
          size: widget.size,
          pitch: _pitch,
          yaw: _yaw,
          roll: 0,
          vertices: vertices,
          color: widget.color,
          faces: faces,
          zoom: 200,
        ),
      ),
    );
  }
}

class _ObjectPainter extends CustomPainter {
  final Size size;
  final double zoom, pitch, yaw, roll;
  late final double _viewPortX = size.width / 2;
  late final double _viewPortY = size.height / 2;

  final Color color;

  final List<Vector3> vertices;
  final List<List<int>> faces;

  final vmath.Vector3 camera = Vector3(0.0, 0.0, 0.0);
  final vmath.Vector3 light = Vector3(0.0, 0.0, 100.0).normalized();

  _ObjectPainter({
    required this.size,
    required this.pitch,
    required this.yaw,
    required this.roll,
    required this.vertices,
    required this.color,
    required this.faces,
    required this.zoom,
  });

  /// Calculate the normal vector of a face.
  Vector3 _normalVector3(Vector3 first, Vector3 second, Vector3 third) {
    final secondFirst = Vector3.copy(second)..sub(first);
    final secondThird = Vector3.copy(second)..sub(third);
    return Vector3(
      (secondFirst.y * secondThird.z) - (secondFirst.z * secondThird.y),
      (secondFirst.z * secondThird.x) - (secondFirst.x * secondThird.z),
      (secondFirst.x * secondThird.y) - (secondFirst.y * secondThird.x),
    );
  }

  /// Multiply two vectors.
  double _scalarMultiplication(Vector3 first, Vector3 second) {
    return (first.x * second.x) + (first.y * second.y) + (first.z * second.z);
  }

  /// Calculate the position of a vertex in the 3D space based
  /// on the angle of rotation, view-port position and zoom.
  Vector3 _calcVertex(Vector3 vertex) {
    final t =
        vmath.Matrix4.translationValues(_viewPortX, _viewPortY, 0);
    t.scale(zoom, -zoom);
    t.rotateX(_degreeToRadian(pitch));
    t.rotateY(_degreeToRadian(yaw));
    t.rotateZ(_degreeToRadian(roll));
    return t.transform3(vertex);
  }

  /// Convert degree to radian.
  double _degreeToRadian(double degree) {
    return degree * (math.pi / 180.0);
  }

  /// Calculate the 2D-positions of a vertex in the 3D space.
  List<Offset> _drawFace(List<Vector3> vertices, List<int> face) {
    final coordinates = <Offset>[];
    for (var i = 0; i < face.length; i++) {
      double x, y;
      if (i < face.length - 1) {
        final iV = vertices[face[i + 1] - 1];
        x = iV.x.toDouble();
        y = iV.y.toDouble();
      } else {
        final iV = vertices[face[0] - 1];
        x = iV.x.toDouble();
        y = iV.y.toDouble();
      }
      coordinates.add(Offset(x, y));
    }
    return coordinates;
  }

  /// Calculate the normal vector of a face.
  Vector3 _normalVector(List<Vector3> verticesToDraw, List<int> face) {
    final first = verticesToDraw[face[0] - 1];
    final second = verticesToDraw[face[1] - 1];
    final third = verticesToDraw[face[2] - 1];
    return _normalVector3(first, second, third).normalized();
  }

  /// Calculate the color of a vertex based on the
  /// position of the vertex and the light.
  List<Color> _calcColor(Color color, Vector3 normalVector) {
    final s = _scalarMultiplication(normalVector, light);
    final double coefficient = math.max(0, s);
    final c = Color.fromRGBO(
      (color.red * coefficient).round(),
      (color.green * coefficient).round(),
      (color.blue * coefficient).round(),
      1,
    );
    return <Color>[c, c, c];
  }

  /// Order vertices by the distance to the camera.
  List<AvgZ> _sortVertices(List<Vector3> vertices) {
    final avgOfZ = <AvgZ>[];
    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      var z = 0.0;
      for (final i in face) {
        z += vertices[i - 1].z;
      }
      avgOfZ.add(AvgZ(i, z));
    }
    avgOfZ.sort((a, b) => a.z.compareTo(b.z));
    return avgOfZ;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the position of the vertices in the 3D space.
    final verticesToDraw = <vmath.Vector3>[];
    for (final vertex in vertices) {
      final defV = _calcVertex(Vector3.copy(vertex));
      verticesToDraw.add(defV);
    }
    // Order vertices by the distance to the camera.
    final avgOfZ = _sortVertices(verticesToDraw);

    // Calculate the position of the vertices in the 2D space
    // and calculate the colors of the vertices.
    final offsets = <Offset>[];
    final colors = <Color>[];
    for (var i = 0; i < faces.length; i++) {
      final face = faces[avgOfZ[i].index];
      final n = _normalVector(verticesToDraw, face);
      colors.addAll(_calcColor(color, n));
      offsets.addAll(_drawFace(verticesToDraw, face));
    }

    // Draw the vertices.
    final paint = Paint();
    paint.style = PaintingStyle.fill;
    paint.color = color;
    final v = Vertices(VertexMode.triangles, offsets, colors: colors);
    canvas.drawVertices(v, BlendMode.clear, paint);
  }

  @override
  bool shouldRepaint(_ObjectPainter old) =>
      old.vertices != vertices ||
      old.faces != faces ||
      old.pitch != pitch ||
      old.yaw != yaw ||
      old.roll != roll ||
      old.zoom != zoom;
}

class AvgZ {
  int index;
  double z;

  AvgZ(this.index, this.z);
}
