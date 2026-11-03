import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class CurationHistoryItem {
  final String id;
  final String date;
  final String userStory;
  final String weatherBadge;
  final String killingQuote;
  final String userOotdBase64;
  final Map<String, dynamic> luxuryPerfume;
  final Map<String, dynamic> affordablePerfume;
  final String visualizedIngredients;
  final String tpoAnalysis;
  final String base64Image;

  CurationHistoryItem({
    required this.id,
    required this.date,
    required this.userStory,
    this.weatherBadge = 'MOKPO 24°C · 구름 조금',
    this.killingQuote = '오늘의 시그니처 향기',
    this.userOotdBase64 = '',
    required this.luxuryPerfume,
    required this.affordablePerfume,
    required this.visualizedIngredients,
    required this.tpoAnalysis,
    required this.base64Image,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'userStory': userStory,
        'weatherBadge': weatherBadge,
        'killingQuote': killingQuote,
        'userOotdBase64': userOotdBase64,
        'luxuryPerfume': luxuryPerfume,
        'affordablePerfume': affordablePerfume,
        'visualizedIngredients': visualizedIngredients,
        'tpoAnalysis': tpoAnalysis,
        'base64Image': base64Image,
      };

  factory CurationHistoryItem.fromJson(Map<String, dynamic> json) {
    return CurationHistoryItem(
      id: json['id'] ?? '',
      date: json['date'] ?? '',
      userStory: json['userStory'] ?? '',
      weatherBadge: json['weatherBadge'] ?? 'MOKPO 24°C · 구름 조금',
      killingQuote: json['killingQuote'] ?? '오늘의 시그니처 향기',
      userOotdBase64: json['userOotdBase64'] ?? '',
      luxuryPerfume: Map<String, dynamic>.from(json['luxuryPerfume'] ?? {}),
      affordablePerfume: Map<String, dynamic>.from(json['affordablePerfume'] ?? {}),
      visualizedIngredients: json['visualizedIngredients'] ?? '',
      tpoAnalysis: json['tpoAnalysis'] ?? '',
      base64Image: json['base64Image'] ?? '',
    );
  }

  // ==========================================
  // 클라우드 DB (Firebase Firestore) 관리 메서드
  // - 컬렉션 'history'에 기록 1개 = 문서 1개로 저장
  // - 사진은 Firestore 문서 용량(1MB) 안에 들어가도록 썸네일로 줄여서 저장
  // ==========================================
  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('history');

  static Future<List<CurationHistoryItem>> getHistory() async {
    try {
      final snapshot =
          await _collection.orderBy('createdAt', descending: true).get();
      return snapshot.docs
          .map((doc) => CurationHistoryItem.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('진열장 불러오기 실패: $e');
      return [];
    }
  }

  /// 저장 성공 여부를 반환합니다. (실패해도 추천 결과 화면은 그대로 보여주기 위함)
  static Future<bool> saveHistory(CurationHistoryItem newItem) async {
    try {
      final data = newItem.toJson()
        ..['userOotdBase64'] = toThumbnail(newItem.userOotdBase64)
        ..['createdAt'] = FieldValue.serverTimestamp();
      await _collection.doc(newItem.id).set(data);
      return true;
    } catch (e) {
      debugPrint('진열장 저장 실패: $e');
      return false;
    }
  }

  static Future<void> deleteHistoryItem(String id) async {
    try {
      await _collection.doc(id).delete();
    } catch (e) {
      debugPrint('진열장 삭제 실패: $e');
    }
  }

  static Future<void> clearAll() async {
    try {
      final snapshot = await _collection.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('진열장 비우기 실패: $e');
    }
  }

  // 착장 사진(수 MB)을 가로 480px JPEG 썸네일(수십 KB)로 축소
  static String toThumbnail(String base64Str) {
    if (base64Str.isEmpty) return '';
    try {
      final decoded = img.decodeImage(base64Decode(base64Str));
      if (decoded == null) return '';
      final resized =
          decoded.width > 480 ? img.copyResize(decoded, width: 480) : decoded;
      return base64Encode(img.encodeJpg(resized, quality: 75));
    } catch (_) {
      return '';
    }
  }
}
