import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ==========================================
// Firestore 컬렉션 관리 (진열장 외 기능)
// - feedback: 향수별 👍(1) / 👎(-1). 서버가 다음 추천에 반영
// - wishlist: 사고 싶은 향수 모음
// - recommendation_logs: 서버가 남기는 AI 검증 로그 (앱은 읽기만)
// ==========================================
class ScentStore {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------- 피드백 ----------------
  static Future<int> getVote(String perfumeId) async {
    if (perfumeId.isEmpty) return 0;
    try {
      final doc = await _db.collection('feedback').doc(perfumeId).get();
      return (doc.data()?['vote'] as int?) ?? 0;
    } catch (e) {
      debugPrint('피드백 불러오기 실패: $e');
      return 0;
    }
  }

  /// vote: 1(좋아요), -1(별로예요), 0(취소)
  static Future<bool> setVote(Map<String, dynamic> perfume, int vote) async {
    final id = perfume['id'] as String? ?? '';
    if (id.isEmpty) return false;
    try {
      final ref = _db.collection('feedback').doc(id);
      if (vote == 0) {
        await ref.delete();
      } else {
        await ref.set({
          'perfumeId': id,
          'brand': perfume['brand'] ?? '',
          'name': perfume['name'] ?? '',
          'accords': perfume['accords'] ?? [],
          'vote': vote,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return true;
    } catch (e) {
      debugPrint('피드백 저장 실패: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllFeedback() async {
    try {
      final snapshot = await _db.collection('feedback').get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('피드백 목록 실패: $e');
      return [];
    }
  }

  // ---------------- 위시리스트 ----------------
  static Future<bool> isWished(String perfumeId) async {
    if (perfumeId.isEmpty) return false;
    try {
      final doc = await _db.collection('wishlist').doc(perfumeId).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setWished(Map<String, dynamic> perfume, bool wished) async {
    final id = perfume['id'] as String? ?? '';
    if (id.isEmpty) return false;
    try {
      final ref = _db.collection('wishlist').doc(id);
      if (wished) {
        // 위시리스트에는 사실 정보만 보관 (AI 문구 제외)
        await ref.set({
          'perfumeId': id,
          'perfume': factSnapshot(perfume),
          'addedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.delete();
      }
      return true;
    } catch (e) {
      debugPrint('위시리스트 저장 실패: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getWishlist() async {
    try {
      final snapshot = await _db
          .collection('wishlist')
          .orderBy('addedAt', descending: true)
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('위시리스트 불러오기 실패: $e');
      return [];
    }
  }

  // ---------------- 착용 캘린더 ----------------
  // 문서 id = 'yyyy-MM-dd' (하루에 하나, 다시 고르면 덮어씀)
  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 진열장 날짜 표기('2026.11.01')를 착용 기록 키('2026-11-01')로 변환
  static String dateKeyFromHistory(String historyDate) =>
      historyDate.replaceAll('.', '-');

  static Map<String, dynamic> factSnapshot(Map<String, dynamic> perfume) => {
        for (final key in [
          'id', 'brand', 'name', 'tier', 'scent_notes', 'accords', 'gender', 'year',
          'top_notes', 'middle_notes', 'base_notes', 'notes', 'source_url'
        ])
          if (perfume[key] != null) key: perfume[key],
      };

  static Future<bool> setWear({
    required String dateKey,
    required Map<String, dynamic> perfume,
    String historyId = '',
    String ootdThumb = '',
    String userStory = '',
  }) async {
    try {
      await _db.collection('wear_log').doc(dateKey).set({
        'dateKey': dateKey,
        'perfume': factSnapshot(perfume),
        'historyId': historyId,
        'ootdThumb': ootdThumb,
        'userStory': userStory,
        'source': historyId.isEmpty ? 'manual' : 'recommendation',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('착용 기록 저장 실패: $e');
      return false;
    }
  }

  static Future<Map<String, Map<String, dynamic>>> getWearLog() async {
    try {
      final snapshot = await _db.collection('wear_log').get();
      return {for (final d in snapshot.docs) d.id: d.data()};
    } catch (e) {
      debugPrint('착용 기록 불러오기 실패: $e');
      return {};
    }
  }

  static Future<void> deleteWear(String dateKey) async {
    try {
      await _db.collection('wear_log').doc(dateKey).delete();
    } catch (e) {
      debugPrint('착용 기록 삭제 실패: $e');
    }
  }

  // ---------------- AI 검증 로그 ----------------
  static Future<List<Map<String, dynamic>>> getLogs({int limit = 100}) async {
    try {
      final snapshot = await _db
          .collection('recommendation_logs')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('추천 로그 불러오기 실패: $e');
      return [];
    }
  }
}
