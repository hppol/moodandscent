import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/curation_history.dart';
import '../services/scent_store.dart';
import '../utils/scent_labels.dart';
import '../widgets/photo_viewer.dart';
import 'search_screen.dart';
import 'wear_detail_screen.dart';

// 홈 화면 📅 아이콘으로 여는 독립 화면 (진열장 기록을 불러와 캘린더에 전달)
class WearCalendarScreen extends StatefulWidget {
  const WearCalendarScreen({super.key});

  @override
  State<WearCalendarScreen> createState() => _WearCalendarScreenState();
}

class _WearCalendarScreenState extends State<WearCalendarScreen> {
  List<CurationHistoryItem>? _history;

  @override
  void initState() {
    super.initState();
    CurationHistoryItem.getHistory().then((items) {
      if (mounted) setState(() => _history = items);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF222222)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'WEAR CALENDAR',
          style: GoogleFonts.cormorantGaramond(
            letterSpacing: 3.5,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF1E1E1E),
          ),
        ),
      ),
      body: _history == null
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : WearCalendarView(history: _history!),
    );
  }
}

// ==========================================
// 착용 캘린더: 진열장(받은 추천 전부) 중 '실제로 입고 뿌린 것'만 날짜별로 기록
// - 날짜 칸에는 향수 이름 (칸이 넓으면 브랜드도), 사진 유무와 관계없이 같은 모양
// - 날짜를 누르면 달력 아래에 그날 카드 (기록이 없으면 그날 받은 추천에서 고르기)
// Firestore 'wear_log' (문서 id = yyyy-MM-dd)
// ==========================================
class WearCalendarView extends StatefulWidget {
  final List<CurationHistoryItem> history;

  const WearCalendarView({super.key, required this.history});

  @override
  State<WearCalendarView> createState() => _WearCalendarViewState();
}

const _luxuryTint = Color(0xFFEFE6D8);
const _affordableTint = Color(0xFFE5ECE0);
const _accent = Color(0xFF8C7B65);

class _WearCalendarViewState extends State<WearCalendarView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _selected = ScentStore.dateKey(DateTime.now());
  bool _changing = false; // 기록된 날짜에서 '바꾸기'를 누른 상태
  Map<String, Map<String, dynamic>> _wear = {};
  bool _isLoading = true;
  final GlobalKey _panelKey = GlobalKey();
  bool _sideBySide = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wear = await ScentStore.getWearLog();
    if (mounted) {
      setState(() {
        _wear = wear;
        _isLoading = false;
        _changing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    final monthPrefix = '${_month.year}-${_month.month.toString().padLeft(2, '0')}-';
    final monthEntries = _wear.entries.where((e) => e.key.startsWith(monthPrefix)).toList();
    final counts = <String, int>{};
    for (final e in monthEntries) {
      final p = Map<String, dynamic>.from(e.value['perfume'] ?? {});
      final label = '${p['brand'] ?? ''} ${p['name'] ?? ''}'.trim();
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final favorite = counts.entries.isEmpty
        ? null
        : (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;

    final calendar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Color(0xFF5E5446)),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            ),
            Text('${_month.year}년 ${_month.month}월',
                style: GoogleFonts.notoSans(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1F1F1F))),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Color(0xFF5E5446)),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        Text(
          monthEntries.isEmpty
              ? '이번 달 착용 기록이 없어요. 날짜를 눌러 그날 뿌린 향수를 기록해 보세요.'
              : '이번 달 착용 ${monthEntries.length}일 · 가장 많이 뿌린 향수: ${favorite!.key} (${favorite.value}회)',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSans(fontSize: 12, height: 1.45, color: const Color(0xFF5E5446)),
        ),
        const SizedBox(height: 8),
        // 범례
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(_luxuryTint, '럭셔리'),
            const SizedBox(width: 12),
            _legend(_affordableTint, '가성비'),
            const SizedBox(width: 12),
            const Icon(Icons.photo_camera_outlined, size: 12, color: Color(0xFF8C8374)),
            const SizedBox(width: 3),
            Text('착장 사진 있음', style: GoogleFonts.notoSans(fontSize: 10.5, color: const Color(0xFF8C8374))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: ['일', '월', '화', '수', '목', '금', '토']
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: GoogleFonts.notoSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: d == '일' ? const Color(0xFFB0605F) : const Color(0xFF8C8374))),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        _buildGrid(),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      // 화면이 넓으면 달력 옆에, 좁으면 달력 아래에 선택한 날짜 카드
      _sideBySide = constraints.maxWidth >= 820;
      if (_sideBySide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 560,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 8, 32), children: [calendar]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 48, 24, 32),
                children: [_buildDayPanel()],
              ),
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: calendar),
          ),
          const SizedBox(height: 18),
          Container(key: _panelKey, child: _buildDayPanel()),
        ],
      );
    });
  }

  // 날짜 선택 → 좁은 화면에서는 아래 카드가 보이도록 자동 스크롤
  void _select(String key) {
    setState(() {
      _selected = key;
      _changing = false;
    });
    if (_sideBySide) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _panelKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.0);
      }
    });
  }

  Widget _legend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFD9D1C3)),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.notoSans(fontSize: 10.5, color: const Color(0xFF8C8374))),
      ],
    );
  }

  Widget _buildGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday % 7; // 일요일 시작
    final cells = leading + daysInMonth;
    final today = ScentStore.dateKey(DateTime.now());

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cells + (7 - cells % 7) % 7,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, i) {
        final day = i - leading + 1;
        if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
        final key = ScentStore.dateKey(DateTime(_month.year, _month.month, day));
        return GestureDetector(
          onTap: () => _select(key),
          child: _dayCell(day, _wear[key], isToday: key == today, isSelected: key == _selected),
        );
      },
    );
  }

  // 날짜 칸: 칸 너비에 맞춰 글자 크기 조절, 넓으면 브랜드 + 이름, 좁으면 이름만
  Widget _dayCell(int day, Map<String, dynamic>? entry, {required bool isToday, required bool isSelected}) {
    final perfume = Map<String, dynamic>.from(entry?['perfume'] ?? {});
    final hasPhoto = ((entry?['ootdThumb'] ?? '') as String).isNotEmpty;
    final tint = entry == null
        ? Colors.white
        : perfume['tier'] == 'luxury'
            ? _luxuryTint
            : _affordableTint;

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final nameSize = (w * 0.14).clamp(8.0, 13.0);
      final showBrand = w >= 70;
      return Container(
        padding: EdgeInsets.all((w * 0.06).clamp(3.0, 8.0)),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _accent : const Color(0xFFECE7DE),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isToday ? 4 : 0),
                  decoration: isToday
                      ? BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(6))
                      : null,
                  child: Text('$day',
                      style: GoogleFonts.notoSans(
                          fontSize: (w * 0.16).clamp(10.0, 14.0),
                          fontWeight: FontWeight.w700,
                          color: isToday ? Colors.white : const Color(0xFF3B352D))),
                ),
                const Spacer(),
                if (hasPhoto)
                  Icon(Icons.photo_camera_outlined, size: (w * 0.15).clamp(9.0, 14.0), color: const Color(0xFF8C8374)),
              ],
            ),
            if (entry != null) ...[
              const Spacer(),
              if (showBrand)
                Text(perfume['brand'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSans(fontSize: nameSize * 0.82, color: _accent, height: 1.2)),
              Text(perfume['name'] ?? '',
                  maxLines: showBrand ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSans(
                      fontSize: nameSize, fontWeight: FontWeight.w600, height: 1.2, color: const Color(0xFF2B2824))),
            ],
          ],
        ),
      );
    });
  }

  String _dayLabel(String key) {
    final p = key.split('-');
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    return '${d.month}월 ${d.day}일 (${weekdays[d.weekday % 7]})';
  }

  CurationHistoryItem? _historyOf(Map<String, dynamic> entry) {
    final id = entry['historyId'] as String? ?? '';
    if (id.isEmpty) return null;
    for (final h in widget.history) {
      if (h.id == id) return h;
    }
    return null;
  }

  // ---------------- 달력 아래: 선택한 날짜 카드 ----------------
  Widget _buildDayPanel() {
    final entry = _wear[_selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(_dayLabel(_selected),
                style: GoogleFonts.notoSans(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1F1F1F))),
            const Spacer(),
            if (entry != null && !_changing) ...[
              TextButton(onPressed: () => setState(() => _changing = true), child: const Text('바꾸기')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF9A5B4F)),
                onPressed: () async {
                  await ScentStore.deleteWear(_selected);
                  _load();
                },
                child: const Text('삭제'),
              ),
            ],
            if (_changing)
              TextButton(onPressed: () => setState(() => _changing = false), child: const Text('취소')),
          ],
        ),
        const SizedBox(height: 6),
        if (entry != null && !_changing) _entryCard(entry) else _pickOptions(),
      ],
    );
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final perfume = Map<String, dynamic>.from(entry['perfume'] ?? {});
    final photo = (entry['ootdThumb'] ?? '') as String;
    final history = _historyOf(entry);
    final story = ((entry['userStory'] ?? '') as String).isNotEmpty
        ? entry['userStory'] as String
        : (history?.userStory ?? '');
    final accords = List<String>.from(perfume['accords'] ?? []).take(3).map(accordLabel).join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WearDetailScreen(dateLabel: _dayLabel(_selected), entry: entry, history: history),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECE7DE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo.isNotEmpty) ...[
              TapToZoomPhoto(base64Image: photo, maxHeight: 120, radius: 10, center: false),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(perfume['tier'] == 'luxury' ? '👑 럭셔리 니치' : '🌿 가성비 데일리',
                      style: GoogleFonts.notoSans(fontSize: 11, color: _accent)),
                  const SizedBox(height: 4),
                  Text((perfume['brand'] ?? '').toString().toUpperCase(),
                      style: GoogleFonts.cormorantGaramond(
                          fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 2, color: _accent)),
                  Text(perfume['name'] ?? '',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF1F1F1F))),
                  if (accords.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(accords, style: GoogleFonts.notoSans(fontSize: 11.5, color: const Color(0xFF8C8374))),
                  ],
                  if (story.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('"$story"',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSans(fontSize: 12, height: 1.45, color: const Color(0xFF5E5446))),
                  ],
                  const SizedBox(height: 8),
                  Text('자세히 보기 ▸',
                      style: GoogleFonts.notoSans(fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 기록이 없는 날(또는 바꾸기): 그날 받은 추천 중에서 고르거나, 검색해서 직접 기록
  Widget _pickOptions() {
    final historyDate = _selected.replaceAll('-', '.');
    final dayItems = widget.history.where((h) => h.date == historyDate).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          dayItems.isEmpty
              ? '이날 받은 추천이 없어요. 향수를 검색해서 직접 기록할 수 있어요.'
              : '이날 받은 추천 ${dayItems.length}개 중에서 실제로 입고 뿌린 향수를 골라주세요.',
          style: GoogleFonts.notoSans(fontSize: 12, color: const Color(0xFF8C8374)),
        ),
        const SizedBox(height: 10),
        ...dayItems.map(_historyOption),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await Navigator.push<Map<String, dynamic>>(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen(pickMode: true)),
            );
            if (picked != null) {
              await ScentStore.setWear(dateKey: _selected, perfume: picked);
              _load();
            }
          },
          icon: const Icon(Icons.search, size: 18),
          label: const Text('향수 검색해서 직접 기록'),
        ),
      ],
    );
  }

  Widget _historyOption(CurationHistoryItem item) {
    Widget choice(Map<String, dynamic> perfume, String tag, Color tint) {
      return Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            backgroundColor: tint,
            side: const BorderSide(color: Color(0xFFE0D8CA)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () async {
            await ScentStore.setWear(
              dateKey: _selected,
              perfume: perfume,
              historyId: item.id,
              ootdThumb: item.userOotdBase64, // 진열장에는 이미 썸네일로 저장되어 있음
              userStory: item.userStory,
            );
            _load();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tag, style: GoogleFonts.notoSans(fontSize: 10, color: _accent)),
              Text(perfume['brand'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSans(fontSize: 10.5, color: const Color(0xFF6B6357))),
              Text(perfume['name'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF2B2824))),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECE7DE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.userOotdBase64.isNotEmpty) ...[
            TapToZoomPhoto(base64Image: item.userOotdBase64, maxHeight: 96, radius: 8, center: false),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.userStory.isEmpty ? '(사진 없이 받은 추천)' : item.userStory,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSans(fontSize: 11.5, color: const Color(0xFF5E5446))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    choice(item.luxuryPerfume, '👑 럭셔리', _luxuryTint),
                    const SizedBox(width: 6),
                    choice(item.affordablePerfume, '🌿 가성비', _affordableTint),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
