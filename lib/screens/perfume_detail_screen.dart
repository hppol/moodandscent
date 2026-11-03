import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/curation_history.dart';
import '../services/scent_store.dart';
import '../widgets/note_pyramid.dart';
import '../widgets/reaction_bar.dart';

// ==========================================
// 향수 상세: 기본 정보 · 👍/👎/♡ · 노트 피라미드 · 비슷한 향수 · 나와의 기록 · Fragrantica 링크
// pickMode: 착용 캘린더에 기록할 향수를 골라 Navigator.pop으로 돌려줌
// ==========================================
class PerfumeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> perfume;
  final bool pickMode;

  const PerfumeDetailScreen({super.key, required this.perfume, this.pickMode = false});

  @override
  State<PerfumeDetailScreen> createState() => _PerfumeDetailScreenState();
}

class _PerfumeDetailScreenState extends State<PerfumeDetailScreen> {
  List<Map<String, dynamic>> _similar = [];
  bool _similarLoading = true;
  List<String> _recommendedDates = [];
  List<String> _wornDates = [];

  Map<String, dynamic> get p => widget.perfume;
  String get _id => p['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _loadSimilar();
    _loadMyRecords();
  }

  Future<void> _loadSimilar() async {
    try {
      final uri = Uri.parse('$kApiBaseUrl/perfumes/similar')
          .replace(queryParameters: {'id': _id, 'limit': '5'});
      final res = await http.get(uri);
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (mounted) {
        setState(() {
          _similar = List<Map<String, dynamic>>.from(data['results'] ?? []);
          _similarLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _similarLoading = false);
    }
  }

  // 진열장(추천받은 날)과 착용 캘린더(실제로 뿌린 날)에서 이 향수 찾기
  Future<void> _loadMyRecords() async {
    final results = await Future.wait([CurationHistoryItem.getHistory(), ScentStore.getWearLog()]);
    final history = results[0] as List<CurationHistoryItem>;
    final wear = results[1] as Map<String, Map<String, dynamic>>;
    if (!mounted) return;
    setState(() {
      _recommendedDates = history
          .where((h) => h.luxuryPerfume['id'] == _id || h.affordablePerfume['id'] == _id)
          .map((h) => h.date)
          .toSet()
          .toList();
      _wornDates = wear.entries
          .where((e) => (e.value['perfume'] as Map?)?['id'] == _id)
          .map((e) => e.key.replaceAll('-', '.'))
          .toList()
        ..sort((a, b) => b.compareTo(a));
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (p['year'] != null) '${p['year']}년 출시',
      if ((p['gender'] ?? '').toString().isNotEmpty) p['gender'],
      if (p['rating'] != null && p['rating_count'] != null)
        '평점 ${p['rating']} (리뷰 ${_formatCount(p['rating_count'])}개)',
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF222222)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        children: [
          Text(p['tier'] == 'luxury' ? '👑 럭셔리 니치' : '🌿 가성비 데일리',
              style: GoogleFonts.notoSans(fontSize: 12, color: const Color(0xFF8C7B65))),
          const SizedBox(height: 6),
          Text((p['brand'] ?? '').toString().toUpperCase(),
              style: GoogleFonts.cormorantGaramond(
                  fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 2.8, color: const Color(0xFF8C7B65))),
          Text(p['name'] ?? '',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 28, fontWeight: FontWeight.w700, height: 1.2, color: const Color(0xFF1F1F1F))),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(meta.join(' · '),
                style: GoogleFonts.notoSans(fontSize: 12.5, color: const Color(0xFF8C8374))),
          ],
          const SizedBox(height: 18),
          ReactionBar(perfume: p),

          _sectionTitle('향 구조'),
          NotePyramid(perfume: p),

          _sectionTitle('비슷한 향수'),
          if (_similarLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF8C7B65))),
            )
          else if (_similar.isEmpty)
            _hint('비슷한 향수를 불러오지 못했어요. AI 서버가 켜져 있는지 확인해 주세요.')
          else
            ..._similar.map(_similarTile),

          _sectionTitle('나와의 기록'),
          _recordCard(),

          const SizedBox(height: 10),
          Center(child: FragranticaLinkButton(url: p['source_url'] ?? '')),

          if (widget.pickMode) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8C7B65),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context, p),
              icon: const Icon(Icons.event_available, size: 18),
              label: const Text('이 향수로 착용 기록'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCount(dynamic n) {
    final s = n.toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 10),
      child: Text(text,
          style: GoogleFonts.notoSans(
              fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1F1F1F))),
    );
  }

  Widget _hint(String text) {
    return Text(text, style: GoogleFonts.notoSans(fontSize: 12.5, color: const Color(0xFF8C8374)));
  }

  Widget _similarTile(Map<String, dynamic> s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PerfumeDetailScreen(perfume: s, pickMode: widget.pickMode)),
        ).then((picked) {
          // 비슷한 향수 화면에서 착용 기록용으로 골랐다면 그대로 전달
          if (picked != null && widget.pickMode && mounted) Navigator.pop(context, picked);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECE7DE)),
          ),
          child: Row(
            children: [
              Text(s['tier'] == 'luxury' ? '👑' : '🌿', style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s['brand']} · ${s['name']}',
                        style: GoogleFonts.notoSans(
                            fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF2B2824))),
                    const SizedBox(height: 2),
                    Text(s['match_reason'] ?? '',
                        style: GoogleFonts.notoSans(fontSize: 11.5, color: const Color(0xFF6B7A62))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFB5AC9E)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordCard() {
    final lines = <String>[
      _recommendedDates.isEmpty
          ? '아직 추천받은 적 없는 향수예요.'
          : '추천받은 날 ${_recommendedDates.length}번 · ${_recommendedDates.take(3).join(', ')}${_recommendedDates.length > 3 ? ' …' : ''}',
      _wornDates.isEmpty
          ? '착용 캘린더에 기록한 적이 없어요.'
          : '실제로 뿌린 날 ${_wornDates.length}번 · ${_wornDates.take(3).join(', ')}${_wornDates.length > 3 ? ' …' : ''}',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E3D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(l,
                      style: GoogleFonts.notoSans(fontSize: 12.5, height: 1.45, color: const Color(0xFF5E5446))),
                ))
            .toList(),
      ),
    );
  }
}
