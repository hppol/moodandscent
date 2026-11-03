import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/curation_history.dart';
import '../services/scent_store.dart';
import '../utils/scent_labels.dart';

// 인사이트: [취향 리포트] 진열장·피드백 기반 향 계열 통계 / [AI 검증 로그] 서버가 남긴 추천 기록
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

const _ink = Color(0xFF1F1F1F);
const _inkSecondary = Color(0xFF5E5446);
const _inkMuted = Color(0xFF8C8374);
const _accent = Color(0xFF8C7B65);
const _track = Color(0xFFEFEAE1);
const _border = Color(0xFFECE7DE);

class _InsightsScreenState extends State<InsightsScreen> {
  bool _isLoading = true;
  List<CurationHistoryItem> _history = [];
  List<Map<String, dynamic>> _feedback = [];
  List<Map<String, dynamic>> _wishlist = [];
  List<Map<String, dynamic>> _logs = [];
  Map<String, Map<String, dynamic>> _wear = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      CurationHistoryItem.getHistory(),
      ScentStore.getAllFeedback(),
      ScentStore.getWishlist(),
      ScentStore.getLogs(),
      ScentStore.getWearLog(),
    ]);
    if (!mounted) return;
    setState(() {
      _history = results[0] as List<CurationHistoryItem>;
      _feedback = results[1] as List<Map<String, dynamic>>;
      _wishlist = results[2] as List<Map<String, dynamic>>;
      _logs = results[3] as List<Map<String, dynamic>>;
      _wear = results[4] as Map<String, Map<String, dynamic>>;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: Color(0xFF222222)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'SCENT INSIGHTS',
            style: GoogleFonts.cormorantGaramond(
              letterSpacing: 3.5,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: const Color(0xFF1E1E1E),
            ),
          ),
          bottom: TabBar(
            labelColor: _ink,
            unselectedLabelColor: _inkMuted,
            indicatorColor: _accent,
            labelStyle:
                GoogleFonts.notoSans(fontSize: 13.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                GoogleFonts.notoSans(fontSize: 13.5, fontWeight: FontWeight.w500),
            tabs: const [Tab(text: '취향 리포트'), Tab(text: 'AI 검증 로그')],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : TabBarView(children: [_buildTasteReport(), _buildLogView()]),
      ),
    );
  }

  // =====================================================================
  // [1] 취향 리포트
  // =====================================================================
  Widget _buildTasteReport() {
    // 진열장 추천 향수의 상위 3개 어코드(1점) + 👍한 향수(2점) + 실제로 뿌린 향수(3점, 가장 강한 신호)
    final scores = <String, double>{};
    final brands = <String, int>{};
    for (final item in _history) {
      for (final p in [item.luxuryPerfume, item.affordablePerfume]) {
        for (final a in List<String>.from(p['accords'] ?? []).take(3)) {
          scores[a] = (scores[a] ?? 0) + 1;
        }
        final brand = p['brand'] as String? ?? '';
        if (brand.isNotEmpty) brands[brand] = (brands[brand] ?? 0) + 1;
      }
    }
    final likes = _feedback.where((f) => f['vote'] == 1).toList();
    for (final f in likes) {
      for (final a in List<String>.from(f['accords'] ?? []).take(3)) {
        scores[a] = (scores[a] ?? 0) + 2;
      }
    }
    for (final w in _wear.values) {
      final p = Map<String, dynamic>.from(w['perfume'] ?? {});
      for (final a in List<String>.from(p['accords'] ?? []).take(3)) {
        scores[a] = (scores[a] ?? 0) + 3;
      }
    }
    final total = scores.values.fold<double>(0, (a, b) => a + b);
    final topAccords = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topBrands = brands.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(
            children: [
              _statTile('진열된 추천', '${_history.length}회'),
              const SizedBox(width: 8),
              _statTile('착용 기록', '${_wear.length}일'),
              const SizedBox(width: 8),
              _statTile('좋아요', '${likes.length}개'),
              const SizedBox(width: 8),
              _statTile('위시', '${_wishlist.length}개'),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle('나의 향 계열 TOP 8',
              '추천받은 향수(1점), 👍한 향수(2점), 실제로 뿌린 향수(3점)의 향 계열로 계산했어요.'),
          const SizedBox(height: 14),
          if (topAccords.isEmpty)
            _emptyHint('추천을 받거나 👍를 누르면 취향 리포트가 채워져요.')
          else
            _card(
              Column(
                children: topAccords.take(8).map((e) {
                  final share = total == 0 ? 0.0 : e.value / total;
                  return _accordBar(accordLabel(e.key), share);
                }).toList(),
              ),
            ),
          if (topBrands.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle('자주 추천된 브랜드', null),
            const SizedBox(height: 12),
            _card(
              Column(
                children: topBrands.take(5).toList().asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text('${e.key + 1}',
                              style: GoogleFonts.notoSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _accent)),
                        ),
                        Expanded(
                          child: Text(e.value.key,
                              style: GoogleFonts.notoSans(
                                  fontSize: 13.5, color: _ink)),
                        ),
                        Text('${e.value.value}회',
                            style: GoogleFonts.notoSans(
                                fontSize: 12.5, color: _inkSecondary)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 단일 계열 가로 막대 (값 라벨은 텍스트 색상, 막대는 한 가지 색)
  Widget _accordBar(String label, double share) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSans(fontSize: 12.5, color: _ink)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: _track,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    height: 10,
                    width: (constraints.maxWidth * share).clamp(4.0, constraints.maxWidth),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text('${(share * 100).round()}%',
                textAlign: TextAlign.right,
                style: GoogleFonts.notoSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _inkSecondary)),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // [2] AI 검증 로그
  // =====================================================================
  Widget _buildLogView() {
    final count = _logs.length;
    final firstTryValid = _logs.where((l) => l['first_try_valid'] == true).length;
    final fallbacks = _logs.where((l) => l['fallback_used'] == true).length;
    final totals = _logs
        .map((l) => (l['timings'] as Map?)?['total'])
        .whereType<num>()
        .toList();
    final avgTotal =
        totals.isEmpty ? 0 : totals.reduce((a, b) => a + b) / totals.length;

    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(
            children: [
              _statTile('총 추천', '$count회'),
              const SizedBox(width: 10),
              _statTile('AI 첫 선택 유효',
                  count == 0 ? '-' : '${(firstTryValid / count * 100).round()}%'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statTile('후보 밖 선택 → 대체', '$fallbacks회'),
              const SizedBox(width: 10),
              _statTile('평균 진단 시간',
                  count == 0 ? '-' : '${avgTotal.toStringAsFixed(1)}초'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF3EC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD9E2D3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_outlined,
                    size: 16, color: Color(0xFF5E7A55)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI는 향수 DB(1,000개)에서 추린 후보 25개 중에서만 고를 수 있어요. '
                    '후보 밖의 답을 하면 다시 묻고, 그래도 틀리면 1순위 후보로 대체돼요. '
                    '향수명·노트는 항상 DB 값을 그대로 보여줘요.',
                    style: GoogleFonts.notoSans(
                        fontSize: 12, height: 1.5, color: const Color(0xFF4A5E43)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _sectionTitle('최근 추천 기록', '항목을 누르면 AI가 본 후보와 선택 과정을 볼 수 있어요.'),
          const SizedBox(height: 12),
          if (_logs.isEmpty)
            _emptyHint('아직 기록이 없어요. 추천을 받으면 여기에 쌓여요.')
          else
            ..._logs.map(_logTile),
        ],
      ),
    );
  }

  Widget _logTile(Map<String, dynamic> log) {
    final created = log['createdAt'];
    final date = created is Timestamp ? created.toDate() : null;
    final dateStr = date == null
        ? ''
        : '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final timings = Map<String, dynamic>.from(log['timings'] ?? {});
    final attempts = List<String>.from(log['ai_attempts'] ?? []);
    final candidateIds = List<String>.from(log['candidate_ids'] ?? []);
    final candidates = List<String>.from(log['candidates'] ?? []);
    final profile = Map<String, dynamic>.from(log['profile'] ?? {});
    final fallback = log['fallback_used'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(
            fallback ? Icons.sync_problem_outlined : Icons.check_circle_outline,
            color: fallback ? const Color(0xFFB08A3E) : const Color(0xFF5E7A55),
            size: 22,
          ),
          title: Text(log['luxury'] ?? '',
              style: GoogleFonts.notoSans(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
          subtitle: Text(
            '$dateStr · ${timings['total'] ?? '-'}초 · ${(log['moodText'] ?? '').toString().replaceAll('\n', ' ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSans(fontSize: 11.5, color: _inkMuted),
          ),
          children: [
            _logLine('검증 결과',
                fallback ? '후보 밖 선택 → 1순위 후보로 대체됨' : '후보 안에서 선택 (통과)'),
            _logLine('가성비 대안',
                '${log['affordable'] ?? ''} (유사도 ${(((log['dupe_similarity'] ?? 0) as num) * 100).round()}%)'),
            if ((profile['summary_kr'] ?? '').toString().isNotEmpty)
              _logLine('AI 해석', profile['summary_kr']),
            _logLine('원하는 계열',
                List<String>.from(profile['accords'] ?? []).map(accordLabel).join(', ')),
            _logLine('AI 답변',
                attempts.map((a) => '${candidateIds.contains(a) ? '✓' : '✗'} $a').join('\n')),
            _logLine('단계별 시간',
                '사진 ${timings['blip'] ?? '-'}s · 해석 ${timings['interpret'] ?? '-'}s · 선택 ${timings['choose'] ?? '-'}s · '
                '문구 ${timings['copy'] ?? '-'}s · 이미지 ${timings['image'] ?? '-'}s'),
            const SizedBox(height: 6),
            Text('AI에게 주어진 후보 ${candidates.length}개',
                style: GoogleFonts.notoSans(
                    fontSize: 12, fontWeight: FontWeight.w700, color: _inkSecondary)),
            const SizedBox(height: 6),
            ...candidates.asMap().entries.map((e) {
              final chosen = e.value == log['luxury'];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Text(
                  '${e.key + 1}. ${e.value}${chosen ? '  ← 선택' : ''}',
                  style: GoogleFonts.notoSans(
                    fontSize: 11.5,
                    fontWeight: chosen ? FontWeight.w700 : FontWeight.w400,
                    color: chosen ? _ink : _inkMuted,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _logLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(label,
                style: GoogleFonts.notoSans(
                    fontSize: 12, fontWeight: FontWeight.w600, color: _inkMuted)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.notoSans(
                    fontSize: 12, height: 1.45, color: _inkSecondary)),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // 공통 위젯
  // =====================================================================
  Widget _statTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.notoSans(fontSize: 11.5, color: _inkMuted)),
            const SizedBox(height: 4),
            Text(value,
                style: GoogleFonts.notoSans(
                    fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.notoSans(
                fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle,
              style: GoogleFonts.notoSans(fontSize: 12, color: _inkMuted)),
        ],
      ],
    );
  }

  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _emptyHint(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSans(fontSize: 12.5, color: _inkMuted)),
    );
  }
}
