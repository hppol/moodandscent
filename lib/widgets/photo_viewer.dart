import 'dart:convert';
import 'package:flutter/material.dart';

// 원본 비율 그대로(잘리지 않게) 작게 보여주고, 누르면 전체 화면으로 확대하는 사진
class TapToZoomPhoto extends StatelessWidget {
  final String base64Image;
  final double maxHeight;
  final double radius;
  // 목록(ListView)처럼 너비를 꽉 채우라고 강제하는 곳에서는 가운데 정렬로 감싸야 비율이 유지됨
  final bool center;

  const TapToZoomPhoto({
    super.key,
    required this.base64Image,
    this.maxHeight = 240,
    this.radius = 14,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(base64Image);
    final photo = GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (dialogContext) => GestureDetector(
          onTap: () => Navigator.pop(dialogContext),
          child: InteractiveViewer(
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        // 높이만 제한하고 너비는 사진 비율에 맞춰지므로 잘리지 않음
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
    return center ? Center(child: photo) : photo;
  }
}
