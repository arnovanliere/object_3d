import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:object_3d/object_3d.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // (uncomment line in Object3D constructor)
  // ignore: unused_element
  Face _fresnel(Face face) {
    final color = Colors.blue;
    final light = Vector3(0.0, 0.0, 100.0).normalized();
    double ln1 = light.dot(face.normal);
    double s1 = 1.0 + face.v1.normalized().dot(face.normal);
    double s2 = 1.0 + face.v2.normalized().dot(face.normal);
    double s3 = 1.0 + face.v3.normalized().dot(face.normal);
    double power = 2;

    Color c = Color.fromRGBO(
        (color.red + math.pow(s1, power).round()).clamp(0, 255),
        (color.green + math.pow(s2, power).round()).clamp(0, 255),
        (color.blue + math.pow(s3, power).round()).clamp(0, 255),
        1.0 - ln1.abs());
    return face..setColors(c, c, c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Object 3D Example'),
      ),
      body: Center(
        child: Object3D(
          size: const Size(400.0, 400.0),
          path: "assets/file.obj",
          //  faceColorFunc: _fresnel, // uncomment to see in action
        ),
      ),
    );
  }
}
