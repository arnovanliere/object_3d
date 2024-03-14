library object_3d;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' as vmath;
import 'package:vector_math/vector_math.dart' show Vector3;

typedef FaceColorFunc = Face Function(Face face);

/// Represents a face (3 vertices) with color data
class Face {
  Vector3 _v1, _v2, _v3;
  Vector3? _cachedNormal;
  Color c1 = Colors.white, c2 = Colors.white, c3 = Colors.white;
  Face(this._v1, this._v2, this._v3);

  void setColors(Color c1, Color c2, Color c3) {
    this.c1 = c1;
    this.c2 = c2;
    this.c3 = c3;
  }

  /// getters
  Vector3 get v1 {
    return _v1;
  }

  Vector3 get v2 {
    return _v2;
  }

  Vector3 get v3 {
    return _v1;
  }

  /// setters - invalidate normal cache
  set v1(Vector3 v) {
    _cachedNormal = null;
    _v1 = v;
  }

  set v2(Vector3 v) {
    _cachedNormal = null;
    _v2 = v;
  }

  set v3(Vector3 v) {
    _cachedNormal = null;
    _v3 = v;
  }

  /// Calculate the unit normal vector of a face and cache the result
  Vector3 get normal {
    if (_cachedNormal != null) return Vector3.copy(_cachedNormal!);

    // Normal needs recalculating
    final p = Vector3.copy(_v2)..sub(_v1);
    final q = Vector3.copy(_v2)..sub(_v3);
    _cachedNormal = p.cross(q).normalized();

    return Vector3.copy(_cachedNormal!);
  }
}

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
    this.faceColorFunc,
  })  : assert(
          object != null || path != null,
          'You must provide an object or a path',
        ),
        assert(
          object == null || path == null,
          'You must provide an object or a path, not both',
        ),
        assert(
          swipeCoef > 0,
          'Parameter swipeCoef must be a positive, non-zero real number.',
        ),
        assert(
          dampCoef >= 0.001 && dampCoef <= 0.999,
          'Parameter dampCoef must be in the range [0.001, 0.999].',
        ),
        assert(
          maxSpeed > 0,
          'Parameter maxSpeed must be positive, non-zero real number.',
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
  final FaceColorFunc? faceColorFunc; // If unset, uses _defaultFaceColor()

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
      final chars =
          line.split(space).where((v) => v.isNotEmpty).toList(growable: false);

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
          faceColorFunc: widget.faceColorFunc,
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

  final FaceColorFunc? faceColorFunc;

  _ObjectPainter({
    required this.size,
    required this.pitch,
    required this.yaw,
    required this.roll,
    required this.vertices,
    required this.color,
    required this.faces,
    required this.zoom,
    this.faceColorFunc,
  });

  /// Calculate the position of a vertex in the 3D space based
  /// on the angle of rotation, view-port position and zoom.
  Vector3 _calcVertex(Vector3 vertex) {
    final t = vmath.Matrix4.translationValues(_viewPortX, _viewPortY, 0);
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

  /// Calculate the color of a vertex based on the
  /// position of the vertex and the light.
  Face _defaultFaceColor(Face face) {
    final s = face.normal.dot(light);
    final coefficient = math.max(0, s);
    final c = Color.fromRGBO(
      (color.red * coefficient).round(),
      (color.green * coefficient).round(),
      (color.blue * coefficient).round(),
      1,
    );
    face.setColors(c, c, c);
    return face;
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
    final List<Offset> offsets = [];
    final List<Color> colors = [];
    for (int i = 0; i < faces.length; i++) {
      final faceIdx = faces[avgOfZ[i].index];

      // Allocate list with a fixed size of 3
      final verts = List.filled(3, Vector3.zero(), growable: false);

      verts[0] = verticesToDraw[faceIdx[0] - 1];
      verts[1] = verticesToDraw[faceIdx[1] - 1];
      verts[2] = verticesToDraw[faceIdx[2] - 1];

      Face face = Face(
        verts[0],
        verts[1],
        verts[2],
      );

      // Fallback on default color func if a custom one is not provided
      face = faceColorFunc?.call(face) ?? _defaultFaceColor(face);

      colors.addAll([face.c1, face.c2, face.c3]);
      offsets.addAll(_drawFace(verticesToDraw, faceIdx));
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
