library object_3d;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:vector_math/vector_math.dart' as v;

class Object3D extends StatefulWidget {
  const Object3D({
    super.key,
    required this.size,
    this.color = Colors.white,
    this.object,
    this.path,
  })  : assert(object != null || path != null,
            'You must provide an object or a path'),
        assert(object == null || path == null,
            'You must provide an object or a path, not both');

  final Size size;
  final String? path;
  final String? object;
  final Color color;

  @override
  State<Object3D> createState() => _Object3DState();
}

class _Object3DState extends State<Object3D> {
  double _angleX = 15.0, _angleY = 45.0;
  double _previousX = 0.0, _previousY = 0.0;

  List<Vector3> vertices = [];
  List<List<int>> faces = [];

  @override
  void initState() {
    if (widget.path != null) {
      // Load the object file from assets
      rootBundle.loadString(widget.path!).then(_parseObj);
    } else if (widget.object != null) {
      // Load the object from a string
      _parseObj(widget.object!);
    }
    super.initState();
  }

  /// Parse the object file.
  void _parseObj(String obj) {
    List<Vector3> vertices = [];
    List<List<int>> faces = [];
    final lines = obj.split("\n");
    for (var line in lines) {
      line = line.replaceAll(RegExp(r"\s+$"), "");
      List<String> chars = line.split(" ");
      if (chars[0] == "v") {
        vertices.add(
          Vector3(
            double.parse(chars[1]),
            double.parse(chars[2]),
            double.parse(chars[3]),
          ),
        );
      } else if (chars[0] == "f") {
        List<int> face = [];
        for (var i = 1; i < chars.length; i++) {
          face.add(int.parse(chars[i].split("/")[0]));
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
  void _updateCube(DragUpdateDetails data) {
    _angleY %= 360.0;
    if (_previousY > data.globalPosition.dx) {
      setState(() => _angleY = _angleY - 1);
    } else {
      setState(() => _angleY = _angleY + 1);
    }
    _previousY = data.globalPosition.dx;

    _angleX %= 360.0;
    if (_previousX > data.globalPosition.dy) {
      setState(() => _angleX = _angleX - 1);
    } else {
      setState(() => _angleX = _angleX + 1);
    }
    _previousX = data.globalPosition.dy;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _updateCube,
      onVerticalDragUpdate: _updateCube,
      child: CustomPaint(
        size: widget.size,
        painter: _ObjectPainter(
          size: widget.size,
          angleX: _angleX,
          angleY: _angleY,
          angleZ: 0,
          vertices: vertices,
          color: widget.color,
          faces: faces,
          zoom: 100,
        ),
      ),
    );
  }
}

class _ObjectPainter extends CustomPainter {
  final Size size;
  final double zoom, angleX, angleY, angleZ;
  late final double _viewPortX = size.width / 2;
  late final double _viewPortY = size.height / 2;

  final Color color;

  final List<Vector3> vertices;
  final List<List<int>> faces;

  final camera = Vector3(0.0, 0.0, 0.0);
  final light = Vector3(0.0, 0.0, 100.0).normalized();

  _ObjectPainter({
    required this.size,
    required this.angleX,
    required this.angleY,
    required this.angleZ,
    required this.vertices,
    required this.color,
    required this.faces,
    required this.zoom,
  });

  /// Calculate the normal vector of a face.
  Vector3 _normalVector3(Vector3 first, Vector3 second, Vector3 third) {
    Vector3 secondFirst = Vector3.copy(second)..sub(first);
    Vector3 secondThird = Vector3.copy(second)..sub(third);
    return Vector3(
        (secondFirst.y * secondThird.z) - (secondFirst.z * secondThird.y),
        (secondFirst.z * secondThird.x) - (secondFirst.x * secondThird.z),
        (secondFirst.x * secondThird.y) - (secondFirst.y * secondThird.x));
  }

  /// Multiply two vectors.
  double _scalarMultiplication(Vector3 first, Vector3 second) {
    return (first.x * second.x) + (first.y * second.y) + (first.z * second.z);
  }

  /// Calculate the position of a vertex in the 3D space based
  /// on the angle of rotation, view-port position and zoom.
  Vector3 _calcVertex(Vector3 vertex) {
    final t = v.Matrix4.translationValues(_viewPortX, _viewPortY, 0);
    t.scale(zoom, -zoom);
    t.rotateX(_degreeToRadian(angleX));
    t.rotateY(_degreeToRadian(angleY));
    t.rotateZ(_degreeToRadian(angleZ));
    return t.transform3(vertex);
  }

  /// Convert degree to radian.
  double _degreeToRadian(double degree) {
    return degree * (math.pi / 180.0);
  }

  /// Calculate the 2D-positions of a vertex in the 3D space.
  List<Offset> _drawFace(List<Vector3> vertices, List<int> face) {
    List<Offset> coordinates = [];
    for (int i = 0; i < face.length; i++) {
      double x, y;
      if (i < face.length - 1) {
        x = vertices[face[i + 1] - 1].x.toDouble();
        y = vertices[face[i + 1] - 1].y.toDouble();
      } else {
        x = vertices[face[0] - 1].x.toDouble();
        y = vertices[face[0] - 1].y.toDouble();
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
    double s = _scalarMultiplication(normalVector, light);
    double coefficient = math.max(0, s);
    Color c = Color.fromRGBO(
      (color.red * coefficient).round(),
      (color.green * coefficient).round(),
      (color.blue * coefficient).round(),
      1,
    );
    return [c, c, c];
  }

  /// Order vertices by the distance to the camera.
  List<AvgZ> _sortVertices(List<Vector3> vertices) {
    final List<AvgZ> avgOfZ = [];
    for (int i = 0; i < faces.length; i++) {
      final face = faces[i];
      double z = 0.0;
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
    List<Vector3> verticesToDraw = [];
    for (final vertex in vertices) {
      final defV = _calcVertex(Vector3.copy(vertex));
      verticesToDraw.add(defV);
    }
    // Order vertices by the distance to the camera.
    final avgOfZ = _sortVertices(verticesToDraw);

    // Calculate the position of the vertices in the 2D space
    // and calculate the colors of the vertices.
    List<Offset> offsets = [];
    List<Color> colors = [];
    for (int i = 0; i < faces.length; i++) {
      List<int> face = faces[avgOfZ[i].index];
      final n = _normalVector(verticesToDraw, face);
      colors.addAll(_calcColor(color, n));
      offsets.addAll(_drawFace(verticesToDraw, face));
    }

    // Draw the vertices.
    Paint paint = Paint();
    paint.style = PaintingStyle.fill;
    paint.color = color;
    final v = Vertices(VertexMode.triangles, offsets, colors: colors);
    canvas.drawVertices(v, BlendMode.clear, paint);
  }

  @override
  bool shouldRepaint(_ObjectPainter old) =>
      old.vertices != vertices ||
      old.faces != faces ||
      old.angleX != angleX ||
      old.angleY != angleY ||
      old.angleZ != angleZ ||
      old.zoom != zoom;
}

class AvgZ {
  int index;
  double z;

  AvgZ(this.index, this.z);
}
