import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/curation_history.dart';
import '../services/scent_store.dart';
import '../utils/image_saver.dart';
import '../widgets/note_pyramid.dart';

class ResultScreen extends StatefulWidget {
  final Map<String, dynamic> luxuryPerfume;
  final Map<String, dynamic> affordablePerfume;
  final String visualizedIngredients;
  final String tpoAnalysis;
  final String base64Image;
  final String weatherBadge;
  final String killingQuote;
  final String userOotdBase64;
  // 착용 캘린더 기록용: 이 결과가 저장된 진열장 기록 id와 날짜('2026.11.01')
  final String historyId;
  final String historyDate;
  final String userStory;
  // 탭 이름 (빠른 추천 '내 향수 안에서' 모드에서는 다른 이름 사용)
  final List<String> tabLabels;

  const ResultScreen({
    super.key,
    required this.luxuryPerfume,
    required this.affordablePerfume,
    required this.visualizedIngredients,
    required this.tpoAnalysis,
    required this.base64Image,
    this.weatherBadge = 'MOKPO 24°C · 구름 조금',
    this.killingQuote = '오늘의 시그니처 향기',
    this.userOotdBase64 = '',
    this.historyId = '',
    this.historyDate = '',
    this.userStory = '',
    this.tabLabels = const ['👑 럭셔리 니치 픽', '🌿 가성비 데일리 대안'],
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  // 0: 럭셔리 니치 픽, 1: 가성비 데일리 듀프
  int _selectedPerfumeIndex = 0;
  final GlobalKey _storyCardKey = GlobalKey();
  bool _isSavingCard = false;

  Map<String, dynamic> get _currentPerfume => _selectedPerfumeIndex == 0
      ? widget.luxuryPerfume
      : widget.affordablePerfume;

  // 향수별 피드백(1/-1/0)과 위시리스트 여부 (index 0: 럭셔리, 1: 가성비)
  final Map<int, int> _votes = {0: 0, 1: 0};
  final Map<int, bool> _wished = {0: false, 1: false};
  // 화면을 열었을 때 이미 눌려 있던 상태 (다른 진열장 기록에서 같은 향수에 누른 경우 안내용)
  final Map<int, bool> _wishedBefore = {0: false, 1: false};
  final Map<int, int> _voteBefore = {0: 0, 1: 0};

  @override
  void initState() {
    super.initState();
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    for (final entry in {0: widget.luxuryPerfume, 1: widget.affordablePerfume}.entries) {
      final id = entry.value['id'] as String? ?? '';
      final vote = await ScentStore.getVote(id);
      final wished = await ScentStore.isWished(id);
      if (!mounted) return;
      setState(() {
        _votes[entry.key] = vote;
        _wished[entry.key] = wished;
        _voteBefore[entry.key] = vote;
        _wishedBefore[entry.key] = wished;
      });
    }
  }

  Future<void> _toggleVote(int vote) async {
    final index = _selectedPerfumeIndex;
    final newVote = _votes[index] == vote ? 0 : vote;
    setState(() => _votes[index] = newVote);
    final ok = await ScentStore.setVote(_currentPerfume, newVote);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!ok
            ? '피드백 저장에 실패했습니다.'
            : newVote == 1
                ? '👍 취향으로 기억할게요. 다음 추천에 비슷한 향을 더 골라드려요.'
                : newVote == -1
                    ? '👎 이 향수는 다음 추천에서 제외할게요.'
                    : '피드백을 취소했습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleWish() async {
    final index = _selectedPerfumeIndex;
    final newValue = !(_wished[index] ?? false);
    setState(() => _wished[index] = newValue);
    final ok = await ScentStore.setWished(_currentPerfume, newValue);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!ok
            ? '위시리스트 저장에 실패했습니다.'
            : newValue
                ? '♡ 위시리스트에 담았습니다.'
                : '위시리스트에서 뺐습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildReactionButton({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? activeColor.withOpacity(0.12) : const Color(0xFFF7F5F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? activeColor : const Color(0xFFE8E3D8)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? activeColor : const Color(0xFF8C8374)),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.notoSans(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? activeColor : const Color(0xFF6B6357),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 좋아요 / 별로예요 / 위시리스트 버튼 줄 (DB 향수 id가 있는 결과에만 표시)
  Widget _buildReactionRow() {
    final index = _selectedPerfumeIndex;
    final vote = _votes[index] ?? 0;
    final notices = [
      if (_wishedBefore[index] == true && _wished[index] == true) '♡ 이미 위시리스트에 담긴 향수예요',
      if (_voteBefore[index] != 0 && _voteBefore[index] == vote)
        vote == 1 ? '👍 전에 좋아요를 누른 향수예요' : '👎 전에 별로예요를 누른 향수예요',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReactionButtons(index, vote),
        if (notices.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            notices.join('  ·  '),
            style: GoogleFonts.notoSans(
                fontSize: 11, color: const Color(0xFF9A8F7E)),
          ),
        ],
      ],
    );
  }

  Widget _buildReactionButtons(int index, int vote) {
    return Row(
      children: [
        _buildReactionButton(
          icon: vote == 1 ? Icons.thumb_up : Icons.thumb_up_outlined,
          label: '좋아요',
          active: vote == 1,
          activeColor: const Color(0xFF5E7A55),
          onTap: () => _toggleVote(1),
        ),
        const SizedBox(width: 8),
        _buildReactionButton(
          icon: vote == -1 ? Icons.thumb_down : Icons.thumb_down_outlined,
          label: '별로예요',
          active: vote == -1,
          activeColor: const Color(0xFF9A5B4F),
          onTap: () => _toggleVote(-1),
        ),
        const SizedBox(width: 8),
        _buildReactionButton(
          icon: (_wished[index] ?? false) ? Icons.favorite : Icons.favorite_border,
          label: '위시',
          active: _wished[index] ?? false,
          activeColor: const Color(0xFFB0605F),
          onTap: _toggleWish,
        ),
      ],
    );
  }

  void _copyToClipboard(BuildContext context) {
    final cur = _currentPerfume;
    final textToCopy = '''
[Mood & Scent AI 큐레이션]
선택 픽: ${widget.tabLabels[_selectedPerfumeIndex]}
브랜드: ${cur['brand']}
향수명: ${cur['name']}
노트: ${cur['scent_notes']}
추천 근거: ${cur['match_reason'] ?? ''}

[👃 어떤 냄새인가요?]
${cur['scent_description_kr'] ?? ''}

[🍸 오늘 당신의 무기 (Vibe Check)]
${cur['reason_kr'] ?? ''}

[🤫 조향사의 귓속말 (에티켓 팁)]
${widget.tpoAnalysis}
''';
    Clipboard.setData(ClipboardData(text: textToCopy.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('향수 큐레이션 정보가 클립보드에 복사되었습니다!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isSavingWear = false;

  // 진열장 기록 날짜(없으면 오늘)를 착용 날짜로 사용
  String get _wearDateKey => widget.historyDate.isNotEmpty
      ? ScentStore.dateKeyFromHistory(widget.historyDate)
      : ScentStore.dateKey(DateTime.now());

  String _wearDateLabel() {
    final parts = _wearDateKey.split('-');
    return parts.length == 3 ? '${int.parse(parts[1])}/${int.parse(parts[2])}' : '';
  }

  Future<void> _saveWear() async {
    setState(() => _isSavingWear = true);
    final ok = await ScentStore.setWear(
      dateKey: _wearDateKey,
      perfume: _currentPerfume,
      historyId: widget.historyId,
      ootdThumb: CurationHistoryItem.toThumbnail(widget.userOotdBase64),
      userStory: widget.userStory,
    );
    if (!mounted) return;
    setState(() => _isSavingWear = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '📅 ${_wearDateLabel()} 착용 기록에 ${_currentPerfume['name']}을(를) 남겼어요. (진열장 → 캘린더)'
            : '착용 기록 저장에 실패했습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // AI가 작성한 문구임을 표시하는 작은 라벨
  Widget _buildAiLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EBE2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'AI 해석',
        style: GoogleFonts.notoSans(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF9E8A68),
        ),
      ),
    );
  }

  // 9:16 인스타 매거진 카드 캡처 및 다운로드
  Future<void> _captureAndSaveStoryCard() async {
    setState(() {
      _isSavingCard = true;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final boundary = _storyCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.5); // 고화질 렌더링
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final fileName =
          'mood_scent_story_${DateTime.now().millisecondsSinceEpoch}.png';

      await downloadImage(pngBytes, fileName);

      if (mounted) {
        Navigator.pop(context); // 팝업 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📸 인스타그램 스토리 매거진 카드가 저장되었습니다!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('카드 저장 중 오류가 발생했습니다: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCard = false;
        });
      }
    }
  }

  // 인스타 스토리 매거진 카드 미리보기 다이얼로그
  void _showInstagramCardModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 9:16 비율 매거진 카드 캡처 대상
              RepaintBoundary(
                key: _storyCardKey,
                child: _buildInstagramMagazineCard(),
              ),

              const SizedBox(height: 18),

              // 다운로드 액션 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSavingCard ? null : _captureAndSaveStoryCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: _isSavingCard
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: Text(
                      _isSavingCard ? '저장 중...' : '갤러리에 이미지 저장 (PNG)',
                      style: GoogleFonts.notoSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 18, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 9:16 인스타 매거진 카드 위젯 빌더
  Widget _buildInstagramMagazineCard() {
    final cur = _currentPerfume;

    return Container(
      width: 340,
      height: 604, // 9:16 인스타 스토리 비율
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF9F5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEBE6DC), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 컴팩트한 비주얼 액자 (AI 무드보드 + 유저 OOTD 사진 조각 스티커)
          SizedBox(
            height: 185,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // AI 생성 무드보드 액자
                Container(
                  width: double.infinity,
                  height: 185,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      base64Decode(widget.base64Image),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                // 유저의 실제 OOTD 착장 폴라로이드 조각
                if (widget.userOotdBase64.isNotEmpty)
                  Positioned(
                    bottom: -8,
                    right: -4,
                    child: Transform.rotate(
                      angle: -0.06,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Image.memory(
                                base64Decode(widget.userOotdBase64),
                                width: 72,
                                height: 92,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'MY OOTD',
                              style: GoogleFonts.cormorantGaramond(
                                fontSize: 8.5,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. 에디터 킬링 카피
          Text(
            '“${widget.killingQuote}”',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
              color: const Color(0xFF26231F),
              height: 1.35,
            ),
          ),

          const SizedBox(height: 14),

          // 3. 향수 브랜드 & 이름 (가성비 대안 및 가격 정보 완전 제거!)
          Center(
            child: Column(
              children: [
                Text(
                  (cur['brand'] ?? '').toUpperCase(),
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.8,
                    color: const Color(0xFF8C7B65),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cur['name'] ?? '',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E1E1E),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. [핵심] 직관적 시향기 설명란 (절대 잘리지 않고 충분히 다 보이도록)
          if ((cur['scent_description_kr'] ?? '').isNotEmpty)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFECE6DC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.air, size: 13, color: Color(0xFF8C7B65)),
                      const SizedBox(width: 5),
                      Text(
                        'SCENT STORY',
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: const Color(0xFF8C7B65),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    cur['scent_description_kr'] ?? '',
                    style: GoogleFonts.notoSans(
                      fontSize: 11,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF38342E),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),

          // 5. 🍸 오늘 당신의 무기 (Vibe Check)
          if ((cur['reason_kr'] ?? '').isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFE7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🍸 ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Text(
                      cur['reason_kr'] ?? '',
                      style: GoogleFonts.notoSans(
                        fontSize: 10.5,
                        height: 1.45,
                        color: const Color(0xFF453F36),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // 6. 하단 감성 서명
          Center(
            child: Text(
              'ATELIER DE PARFUM · KINFOLK ARCHIVE',
              style: GoogleFonts.cormorantGaramond(
                fontSize: 9,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFA69E92),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 생성된 무드보드 이미지 확대 모달
  void _openImagePreview(BuildContext context, Uint8List imageBytes) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(
                imageBytes,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'AI Olfactory Moodboard',
              style: GoogleFonts.cormorantGaramond(
                color: Colors.white,
                fontSize: 15,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = base64Decode(widget.base64Image);
    final cur = _currentPerfume;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F8F6),
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
          'CURATION RESULT',
          style: GoogleFonts.cormorantGaramond(
            letterSpacing: 3.0,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: const Color(0xFF1E1E1E),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. 은은한 앰비언트 배경
          Positioned.fill(
            child: Opacity(
              opacity: 0.18,
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 50.0, sigmaY: 50.0),
              child: Container(color: const Color(0xFFF9F8F6).withOpacity(0.75)),
            ),
          ),

          // 2. 메인 컨텐츠
          SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 날씨 배지 표시
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE8E4DA)),
                      ),
                      child: Text(
                        '🌤️ ${widget.weatherBadge}',
                        style: GoogleFonts.notoSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF7A6F5E),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // -----------------------------------------------------------
                  // [1] AI 생성 무드보드 (향수 노트 오브제 시각화!)
                  // -----------------------------------------------------------
                  Center(
                    child: GestureDetector(
                      onTap: () => _openImagePreview(context, imageBytes),
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 360,
                          maxHeight: 360,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFFEBE6DC),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF221F1A).withOpacity(0.12),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Stack(
                            children: [
                              Image.memory(
                                imageBytes,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.55),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.fullscreen,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 시각화된 향조 오브제 안내 캡션
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE8E4DA)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 13, color: Color(0xFF9E8A68)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '시각화된 향 노트: ${widget.visualizedIngredients}',
                              style: GoogleFonts.notoSans(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF6B5F4D),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // -----------------------------------------------------------
                  // [2] 듀오 추천 탭 (럭셔리 니치 vs 가성비 데일리 듀프)
                  // -----------------------------------------------------------
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECE7DE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPerfumeIndex = 0;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedPerfumeIndex == 0
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: _selectedPerfumeIndex == 0
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    widget.tabLabels[0],
                                    style: GoogleFonts.notoSans(
                                      fontSize: 13,
                                      fontWeight: _selectedPerfumeIndex == 0
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: _selectedPerfumeIndex == 0
                                          ? const Color(0xFF1E1E1E)
                                          : const Color(0xFF756F64),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPerfumeIndex = 1;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedPerfumeIndex == 1
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: _selectedPerfumeIndex == 1
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    widget.tabLabels[1],
                                    style: GoogleFonts.notoSans(
                                      fontSize: 13,
                                      fontWeight: _selectedPerfumeIndex == 1
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: _selectedPerfumeIndex == 1
                                          ? const Color(0xFF1E1E1E)
                                          : const Color(0xFF756F64),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // -----------------------------------------------------------
                  // [3] 선택된 향수 상세 카드
                  // -----------------------------------------------------------
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey<int>(_selectedPerfumeIndex),
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFECE7DE)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 브랜드 & 가격 태그
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  (cur['brand'] ?? '').toUpperCase(),
                                  style: GoogleFonts.cormorantGaramond(
                                    fontSize: 12,
                                    letterSpacing: 2.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFE8DCC4),
                                  ),
                                ),
                              ),
                              // 가격 정보가 있는 경우(이전 기록)에만 표시
                              if ((cur['price_range'] ?? '').isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F5F0),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFE6E1D8)),
                                ),
                                child: Text(
                                  cur['price_range'],
                                  style: GoogleFonts.notoSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF8C7B65),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // 향수 이름
                          Text(
                            cur['name'] ?? '',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1F1F1F),
                              height: 1.25,
                            ),
                          ),

                          const SizedBox(height: 16),

                          if ((cur['id'] ?? '').isNotEmpty) ...[
                            _buildReactionRow(),
                            const SizedBox(height: 16),
                          ],

                          // 프래그런스 노트 피라미드 (탑/하트/베이스 + 주요 향 계열)
                          NotePyramid(perfume: cur),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FragranticaLinkButton(
                                url: cur['source_url'] ?? ''),
                          ),

                          // 추천 근거 (DB 매칭 결과: 취향 키워드 일치 / 럭셔리 픽과의 유사도)
                          if ((cur['match_reason'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF3EC),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: const Color(0xFFD9E2D3)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 1.0),
                                    child: Icon(Icons.verified_outlined,
                                        size: 15, color: Color(0xFF5E7A55)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      cur['match_reason'],
                                      style: GoogleFonts.notoSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF4A5E43),
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // ---------------------------------------------------
                          // [1] 👃 어떤 냄새인가요? (노트 바로 밑 직관적 시향기!)
                          // ---------------------------------------------------
                          if ((cur['scent_description_kr'] ?? '').isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFFFDF9),
                                    Color(0xFFF7F3EB),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color(0xFFE8DFD0), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF9E8A68)
                                        .withOpacity(0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.air,
                                          size: 16, color: Color(0xFF8C7B65)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '어떤 냄새인가요? (직관적 시향기)',
                                        style: GoogleFonts.notoSans(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF2B2824),
                                        ),
                                      ),
                                      const Spacer(),
                                      _buildAiLabel(),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    cur['scent_description_kr'] ?? '',
                                    style: GoogleFonts.notoSans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF3B352D),
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // ---------------------------------------------------
                          // [2] 🍸 오늘 당신의 무기 (Vibe Check)
                          // ---------------------------------------------------
                          if ((cur['reason_kr'] ?? '').isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF8F5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color(0xFFECE7DE)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('🍸',
                                          style: TextStyle(fontSize: 15)),
                                      const SizedBox(width: 6),
                                      Text(
                                        _selectedPerfumeIndex == 0
                                            ? '오늘 당신의 무기 (Vibe Check)'
                                            : '센스 있는 데일리 무기 (Vibe Check)',
                                        style: GoogleFonts.notoSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF22201D),
                                        ),
                                      ),
                                      const Spacer(),
                                      _buildAiLabel(),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    cur['reason_kr'] ?? '',
                                    style: GoogleFonts.notoSans(
                                      fontSize: 13,
                                      color: const Color(0xFF4A443C),
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // ---------------------------------------------------
                          // [3] 🤫 조향사의 귓속말 (에티켓 팁)
                          // ---------------------------------------------------
                          if (widget.tpoAnalysis.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F5F0),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color(0xFFE8E3D8)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('🤫',
                                          style: TextStyle(fontSize: 15)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '조향사의 귓속말 (에티켓 팁)',
                                        style: GoogleFonts.notoSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF22201D),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.tpoAnalysis,
                                    style: GoogleFonts.notoSans(
                                      fontSize: 13,
                                      color: const Color(0xFF4A443C),
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 착용 캘린더에 '실제로 뿌린 향수'로 기록
                  if ((cur['id'] ?? '').isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSavingWear ? null : _saveWear,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8C7B65),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.event_available, size: 18),
                        label: Text(
                          '오늘 이걸로 결정! (${_wearDateLabel()} 착용 기록)',
                          style: GoogleFonts.notoSans(
                              fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // -----------------------------------------------------------
                  // [핵심 액션 버튼들]
                  // 1. 인스타 스토리 카드 저장 버튼
                  // 2. 새로운 OOTD 진단 버튼
                  // -----------------------------------------------------------
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showInstagramCardModal(context),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E1E1E),
                            side: const BorderSide(color: Color(0xFFDED8CE)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 17),
                          label: Text(
                            '카드 저장',
                            style: GoogleFonts.notoSans(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E1E1E),
                            foregroundColor: const Color(0xFFFAF7F2),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18),
                          label: Text(
                            '새로운 OOTD 진단',
                            style: GoogleFonts.notoSans(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 텍스트 클립보드 복사 링크 버튼
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _copyToClipboard(context),
                      icon: const Icon(Icons.copy_outlined,
                          size: 15, color: Color(0xFF756F64)),
                      label: Text(
                        '진단 결과 텍스트 복사하기',
                        style: GoogleFonts.notoSans(
                          fontSize: 12.5,
                          color: const Color(0xFF756F64),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
