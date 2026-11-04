import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/curation_history.dart';
import 'result_screen.dart';
import '../services/scent_store.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<CurationHistoryItem> _historyItems = [];
  bool _isLoading = true;
  // 0: 날짜별 선반 진열장, 1: 날짜별 목록
  int _viewMode = 0;
  // 착용 캘린더에 기록된 조합 (진열장 기록 id → 실제로 뿌린 향수 id), 목록의 '📅 착용' 표시용
  Map<String, String> _wornByHistory = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final results = await Future.wait([CurationHistoryItem.getHistory(), ScentStore.getWearLog()]);
    final wear = results[1] as Map<String, Map<String, dynamic>>;
    if (mounted) {
      setState(() {
        _historyItems = results[0] as List<CurationHistoryItem>;
        _wornByHistory = {
          for (final w in wear.values)
            if ((w['historyId'] ?? '').toString().isNotEmpty)
              w['historyId'] as String: ((w['perfume'] as Map?)?['id'] ?? '').toString(),
        };
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(String id) async {
    await CurationHistoryItem.deleteHistoryItem(id);
    _loadHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('진열장에서 향수가 정리되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFBF9F5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '진열장 비우기',
          style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '지금까지 수집된 모든 향수 컬렉션을 진열장에서 정리하시겠습니까?',
          style: GoogleFonts.notoSans(
            fontSize: 13.5,
            color: const Color(0xFF55504A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: GoogleFonts.notoSans(color: const Color(0xFF7A7062)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB33927),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('전체 비우기'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CurationHistoryItem.clearAll();
      _loadHistory();
    }
  }

  // 길게 누르기(진열장) / 밀어서(목록) 삭제 전 확인
  Future<bool> _confirmDelete(CurationHistoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFBF9F5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('진열장에서 뺄까요?',
            style: GoogleFonts.notoSans(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          '${item.date} · ${item.luxuryPerfume['name'] ?? ''}',
          style: GoogleFonts.notoSans(fontSize: 13, color: const Color(0xFF55504A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소', style: GoogleFonts.notoSans(color: const Color(0xFF7A7062))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('빼기',
                style: GoogleFonts.notoSans(
                    color: const Color(0xFFB33927), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _openResult(CurationHistoryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(
          luxuryPerfume: item.luxuryPerfume,
          affordablePerfume: item.affordablePerfume,
          visualizedIngredients: item.visualizedIngredients,
          tpoAnalysis: item.tpoAnalysis,
          base64Image: item.base64Image,
          weatherBadge: item.weatherBadge,
          killingQuote: item.killingQuote,
          userOotdBase64: item.userOotdBase64,
          historyId: item.id,
          historyDate: item.date,
          userStory: item.userStory,
        ),
      ),
    ).then((_) => _loadHistory()); // 결과 화면에서 착용 기록을 남겼을 수 있음
  }

  // '2026.11.02' → ('11월 2일', '일요일')
  (String, String) _dateLabel(String date) {
    final p = date.split('.');
    if (p.length != 3) return (date, '');
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    const weekdays = ['일요일', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일'];
    return ('${d.month}월 ${d.day}일', weekdays[d.weekday % 7]);
  }

  // 날짜별로 묶기 (진열장 기록은 최신순)
  List<MapEntry<String, List<CurationHistoryItem>>> get _groupedByDate {
    final groups = <String, List<CurationHistoryItem>>{};
    for (final item in _historyItems) {
      groups.putIfAbsent(item.date, () => []).add(item);
    }
    return groups.entries.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0), // 고급 아틀리에 크림 베이지
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF222222)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'MY SCENT ATELIER',
          style: GoogleFonts.cormorantGaramond(
            letterSpacing: 3.5,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF1E1E1E),
          ),
        ),
        actions: [
          if (_historyItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 22, color: Color(0xFF888075)),
              tooltip: '진열장 전체 비우기',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF8C7B65)))
          : _historyItems.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    const SizedBox(height: 4),
                    // 보기 방식 전환 (진열장 / 목록)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECE7DE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildViewToggleBtn(
                            icon: Icons.shelves,
                            label: '진열장',
                            isSelected: _viewMode == 0,
                            onTap: () => setState(() => _viewMode = 0),
                          ),
                          _buildViewToggleBtn(
                            icon: Icons.view_agenda_outlined,
                            label: '목록',
                            isSelected: _viewMode == 1,
                            onTap: () => setState(() => _viewMode = 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _viewMode == 0 ? _buildShelfShowroomView() : _buildListView(),
                    ),
                  ],
                ),
    );
  }

  // 뷰 모드 토글 버튼 빌더
  Widget _buildViewToggleBtn({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 14,
                color: isSelected ? const Color(0xFF1E1E1E) : const Color(0xFF888075)),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? const Color(0xFF1E1E1E) : const Color(0xFF888075),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 날짜 머리글 (진열장·목록 공용)
  Widget _dateHeader(String date) {
    final (day, weekday) = _dateLabel(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(day,
              style: GoogleFonts.playfairDisplay(
                  fontSize: 17,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2B2520))),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(weekday,
                style: GoogleFonts.notoSans(fontSize: 11.5, color: const Color(0xFF9E9282))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(bottom: 6),
              color: const Color(0xFFE2DCCF),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // [보기 1] 진열장: 날짜별 선반 위에 향수병 (선반마다 위에서 비추는 조명)
  // =========================================================================
  Widget _buildShelfShowroomView() {
    final groups = _groupedByDate;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: groups.length + 1,
          itemBuilder: (context, index) {
            if (index == groups.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '향수병을 누르면 그날의 추천을, 길게 누르면 진열장에서 뺄 수 있어요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSans(fontSize: 11, color: const Color(0xFFA69D8F)),
                ),
              );
            }
            final group = groups[index];
            final rows = <List<CurationHistoryItem>>[];
            for (var i = 0; i < group.value.length; i += 3) {
              rows.add(group.value.sublist(i, (i + 3).clamp(0, group.value.length)));
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                children: [
                  _dateHeader(group.key),
                  for (final row in rows) _shelfRow(row),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _shelfRow(List<CurationHistoryItem> row) {
    return Stack(
      children: [
        // 선반 위 조명 (위에서 아래로 퍼지는 따뜻한 빛)
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.1),
                  radius: 1.1,
                  colors: [Color(0xFFFFFBF1), Color(0x00F7F5F0)],
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: row.map(_buildShelfBottleCard).toList(),
            ),
            _buildWoodenShelfPlinth(),
          ],
        ),
      ],
    );
  }

  // 향수병: 금색 뚜껑 → 목 → 유리 바디(무드보드 라벨 + 반사광) → 황동 명판
  Widget _buildShelfBottleCard(CurationHistoryItem item) {
    final luxury = item.luxuryPerfume;
    final brand = (luxury['brand'] ?? '').toString().toUpperCase();
    final name = luxury['name'] ?? '';

    return GestureDetector(
      onTap: () => _openResult(item),
      onLongPress: () async {
        if (await _confirmDelete(item)) _deleteItem(item.id);
      },
      child: SizedBox(
        width: 98,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 뚜껑
            Container(
              width: 34,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4), bottom: Radius.circular(2)),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE9D3A3), Color(0xFFB8955A), Color(0xFF8E6E3B)],
                  stops: [0.0, 0.55, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            // 목
            Container(
              width: 22,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFDCD3C2),
                border: Border.all(color: const Color(0xFFCFC4AF), width: 0.8),
              ),
            ),
            // 유리 바디
            Container(
              width: 90,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24), bottom: Radius.circular(12)),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFFFFF), Color(0xFFF2EDE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFFE0D6C3), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF382A1E).withOpacity(0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // 라벨 창 (AI 무드보드)
                  Positioned(
                    left: 9,
                    right: 9,
                    top: 14,
                    bottom: 10,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (item.base64Image.isNotEmpty)
                            Image.memory(base64Decode(item.base64Image), fit: BoxFit.cover)
                          else
                            Container(color: const Color(0xFFE9E1D3)),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                                stops: const [0.45, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 5,
                            right: 5,
                            bottom: 5,
                            child: Text(
                              brand,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cormorantGaramond(
                                fontSize: 9,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: const Color(0xFFFAF6EE),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 유리 반사광
                  Positioned(
                    left: 4,
                    top: 12,
                    bottom: 16,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.0)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 황동 명판
            Container(
              width: 98,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: const LinearGradient(colors: [Color(0xFFF6EBD3), Color(0xFFE6D3AB)]),
                border: Border.all(color: const Color(0xFFD5C19A)),
              ),
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3A2F22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 원목 선반 (윗면 + 앞면 + 그림자)
  Widget _buildWoodenShelfPlinth() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          height: 7,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
            gradient: LinearGradient(
                colors: [Color(0xFFB59775), Color(0xFFA2835F), Color(0xFFB59775)]),
          ),
        ),
        Container(
          height: 10,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
            gradient: const LinearGradient(
              colors: [Color(0xFF7A5E44), Color(0xFF5A4331)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(0, 5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // [보기 2] 목록: 날짜별 매거진 타임라인 (밀어서 빼기)
  // =========================================================================
  Widget _buildListView() {
    final groups = _groupedByDate;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            for (final group in groups) ...[
              _dateHeader(group.key),
              for (final item in group.value) _listCard(item),
              const SizedBox(height: 10),
            ],
            Text(
              '카드를 왼쪽으로 밀면 진열장에서 뺄 수 있어요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSans(fontSize: 11, color: const Color(0xFFA69D8F)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listCard(CurationHistoryItem item) {
    final luxury = item.luxuryPerfume;
    final affordable = item.affordablePerfume;
    final wornPerfume = _wornByHistory[item.id];

    Widget perfumeChip(Map<String, dynamic> p, String emoji, Color tint) {
      final worn = wornPerfume != null && wornPerfume == p['id'];
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(10),
          border: worn ? Border.all(color: const Color(0xFF8C7B65), width: 1.2) : null,
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${p['brand'] ?? ''}  ',
                    style: GoogleFonts.notoSans(fontSize: 10.5, color: const Color(0xFF8C7B65)),
                  ),
                  TextSpan(
                    text: p['name'] ?? '',
                    style: GoogleFonts.notoSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF2B2824)),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (worn) ...[
              const SizedBox(width: 6),
              Text('📅 착용',
                  style: GoogleFonts.notoSans(
                      fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF8C7B65))),
            ],
          ],
        ),
      );
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(item),
      onDismissed: (_) => _deleteItem(item.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFF1E0DA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFB33927)),
      ),
      child: GestureDetector(
        onTap: () => _openResult(item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFECE7DE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 착장 사진(원본 비율) 또는 무드보드
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.userOotdBase64.isNotEmpty
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 108, maxWidth: 84),
                        child: Image.memory(base64Decode(item.userOotdBase64), fit: BoxFit.contain),
                      )
                    : item.base64Image.isNotEmpty
                        ? Image.memory(base64Decode(item.base64Image),
                            width: 76, height: 76, fit: BoxFit.cover)
                        : Container(width: 76, height: 76, color: const Color(0xFFECE7DE)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '“${item.killingQuote}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 14,
                        height: 1.35,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF26231F),
                      ),
                    ),
                    perfumeChip(luxury, '👑', const Color(0xFFF3ECE0)),
                    if ((affordable['name'] ?? '').toString().isNotEmpty)
                      perfumeChip(affordable, '🌿', const Color(0xFFEAF0E6)),
                    if (item.userStory.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        item.userStory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSans(fontSize: 11, color: const Color(0xFF9A9184)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 진열장 비어있을 때 빈 화면
  // =========================================================================
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEFECE5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.shelves,
              size: 48,
              color: Color(0xFF8C7B65),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '아직 진열된 향수가 없습니다',
            style: GoogleFonts.notoSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF26221D),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '매일의 OOTD와 일상을 진단받고\n나만의 니치 향수 진열장을 완성해보세요.',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSans(
              fontSize: 13,
              color: const Color(0xFF888075),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
            label: Text(
              '첫 향수 진열하러 가기',
              style: GoogleFonts.notoSans(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
