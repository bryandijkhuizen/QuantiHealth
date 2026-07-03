import 'package:flutter/material.dart';

class MetricModel {
  const MetricModel({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.color,
    required this.caption,
    required this.samples,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final Color color;
  final String caption;
  final List<double> samples;
}
