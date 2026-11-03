import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/curation_history.dart';
import 'result_screen.dart';
import 'wear_calendar_view.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<CurationHistoryItem> _historyItems = [];
  bool _isLoading = true;
  // 0: 버추얼 원목 진열장 쇼룸(Shelf View), 1: 에디토리얼 리스트 뷰(List View), 2: 착용 캘린더
  int _viewMode = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final items = await CurationHistoryItem.getHistory();
    if (mounted) {
      setState(() {
        _historyItems = items;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0), // 고급 아틀리에 크림 베이지
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: Color(0xFF222222),
          ),
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
              icon: const Icon(
                Icons.delete_sweep_outlined,
                size: 22,
                color: Color(0xFF888075),
              ),
              tooltip: '진열장 전체 비우기',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF8C7B65)),
            )
          : _historyItems.isEmpty && _viewMode != 2
          ? _buildEmptyState()
          : Column(
              children: [
                const SizedBox(height: 8),

                // 상단 컨트롤 바: 진열장 컬렉션 현황 + 뷰 모드 토글
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 수집된 보틀 수 뱃지 (좁은 화면에서는 줄어듦)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE8E2D6)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                size: 13,
                                color: Color(0xFF8C7B65),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '수집된 향수 ${_historyItems.length}병',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.notoSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF5A5245),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 뷰 모드 스위처 (진열장 쇼룸 vs 상세 리스트)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECE7DE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
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
                            _buildViewToggleBtn(
                              icon: Icons.calendar_month_outlined,
                              label: '캘린더',
                              isSelected: _viewMode == 2,
                              onTap: () => setState(() => _viewMode = 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 메인 쇼룸 화면
                Expanded(
                  child: _viewMode == 0
                      ? _buildShelfShowroomView()
                      : _viewMode == 1
                      ? _buildListView()
                      : WearCalendarView(history: _historyItems),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFF888075),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFF888075),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // [모드 1] 버추얼 원목 선반 쇼룸 뷰 (Virtual Wooden Shelf View - 3열 슬림 보틀)
  // =========================================================================
  Widget _buildShelfShowroomView() {
    // 3개씩 짝지어 선반 층(Row) 구성 (아기자기하고 슬림한 3열 진열장)
    final List<List<CurationHistoryItem?>> shelfRows = [];
    for (int i = 0; i < _historyItems.length; i += 3) {
      final item1 = _historyItems[i];
      final item2 = (i + 1 < _historyItems.length)
          ? _historyItems[i + 1]
          : null;
      final item3 = (i + 2 < _historyItems.length)
          ? _historyItems[i + 2]
          : null;
      shelfRows.add([item1, item2, item3]);
    }

    // 마지막 선반이 꽉 찼으면 다음 향수 수집을 유도하는 빈 슬롯 선반 1개 추가
    if (shelfRows.isNotEmpty && shelfRows.last[2] != null) {
      shelfRows.add([null, null, null]);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          itemCount: shelfRows.length,
          itemBuilder: (context, rowIndex) {
            final triplet = shelfRows[rowIndex];

            return Column(
              children: [
                // 선반 층수 라벨
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFFE2DCCF),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          'SHELF 0${rowIndex + 1}',
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            color: const Color(0xFF9E9282),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: const Color(0xFFE2DCCF),
                        ),
                      ),
                    ],
                  ),
                ),

                // 선반 위에 진열된 3개의 슬림 향수 보틀
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    triplet[0] != null
                        ? _buildShelfBottleCard(triplet[0]!)
                        : _buildEmptyShelfSlot(),
                    triplet[1] != null
                        ? _buildShelfBottleCard(triplet[1]!)
                        : _buildEmptyShelfSlot(),
                    triplet[2] != null
                        ? _buildShelfBottleCard(triplet[2]!)
                        : _buildEmptyShelfSlot(),
                  ],
                ),

                // 입체적인 3D 원목 선반 받침대
                _buildWoodenShelfPlinth(),
              ],
            );
          },
        ),
      ),
    );
  }

  // 선반 위 슬림 향수 보틀 & 황동 미니 명판 카드 (가로 < 세로 수직형 아틀리에 보틀)
  Widget _buildShelfBottleCard(CurationHistoryItem item) {
    final luxury = item.luxuryPerfume;
    final brand = (luxury['brand'] ?? '').toUpperCase();
    final name = luxury['name'] ?? '';

    return GestureDetector(
      onTap: () {
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
        );
      },
      child: SizedBox(
        width: 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 미니 향수 보틀 캡 (Perfume Bottle Cap)
            Container(
              width: 22,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF221F1B),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),

            // 향수 보틀 바디 (가로 96 x 세로 136: 확실한 세로형 슬림 비율!)
            Container(
              width: 96,
              height: 136,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                  bottom: Radius.circular(6),
                ),
                border: Border.all(color: const Color(0xFFE5DEC8), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF382A1E).withOpacity(0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // AI 무드보드 이미지
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                      bottom: Radius.circular(5),
                    ),
                    child: Image.memory(
                      base64Decode(item.base64Image),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),

                  // 은은한 글래스 앰비언트 비네트
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                        bottom: Radius.circular(5),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.52),
                          Colors.transparent,
                          Colors.black.withOpacity(0.42),
                        ],
                      ),
                    ),
                  ),

                  // 상단 브랜드 텍스트
                  Positioned(
                    top: 6,
                    left: 4,
                    right: 20,
                    child: Text(
                      brand,
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: const Color(0xFFFAF6EE),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // 삭제 버튼 (미니멀)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _deleteItem(item.id),
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 9,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),

                  // 하단 유저 착장 미니 폴라로이드 스티커
                  if (item.userOotdBase64.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Image.memory(
                            base64Decode(item.userOotdBase64),
                            width: 24,
                            height: 30,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 5),

            // 선반 위 황동 미니 명판 (Brass Plaque)
            Container(
              width: 96,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2D9CC)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF26221D),
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.date,
                    style: GoogleFonts.notoSans(
                      fontSize: 8.5,
                      color: const Color(0xFF968875),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 선반 위 빈 슬롯 (다음 착장 진열 유도)
  Widget _buildEmptyShelfSlot() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: SizedBox(
        width: 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 보틀 캡 더미
            Container(
              width: 22,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFFDED8CE).withOpacity(0.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
              ),
            ),
            Container(
              width: 96,
              height: 136,
              decoration: BoxDecoration(
                color: const Color(0xFFEFECE5).withOpacity(0.4),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                  bottom: Radius.circular(6),
                ),
                border: Border.all(
                  color: const Color(0xFFDDD5C7),
                  width: 1.2,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE5DEC8).withOpacity(0.8),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 16,
                        color: Color(0xFF8C7B65),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '새 착장 진열',
                      style: GoogleFonts.notoSans(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8C7B65),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 96,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
              decoration: BoxDecoration(
                color: const Color(0xFFECE7DE).withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'EMPTY',
                textAlign: TextAlign.center,
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 9,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFA69D8F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 입체적인 3D 원목 선반 받침대
  Widget _buildWoodenShelfPlinth() {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 24),
      height: 11,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF947B62), // 상단 하이라이트 원목 엣지
            Color(0xFF6B533E), // 메인 월넛 우드
            Color(0xFF483526), // 하단 섀도우
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // [모드 2] 에디토리얼 리스트 뷰 (Editorial List View)
  // =========================================================================
  Widget _buildListView() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      itemCount: _historyItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final item = _historyItems[index];
        final luxury = item.luxuryPerfume;
        final affordable = item.affordablePerfume;

        return GestureDetector(
          onTap: () {
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
            );
          },
          child: Container(
            padding: const EdgeInsets.all(15),
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
                // 무드보드 썸네일
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 85,
                    height: 85,
                    color: const Color(0xFFECE7DE),
                    child: item.base64Image.isNotEmpty
                        ? Image.memory(
                            base64Decode(item.base64Image),
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.image, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 14),

                // 정보 영역
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item.date,
                            style: GoogleFonts.notoSans(
                              fontSize: 11,
                              color: const Color(0xFF8C7B65),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _deleteItem(item.id),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Color(0xFFBDBDBD),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${luxury['brand'] ?? ''} · ${luxury['name'] ?? ''}',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF222222),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((affordable['name'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          '🌿 Dupe: ${affordable['brand']} ${affordable['name']}',
                          style: GoogleFonts.notoSans(
                            fontSize: 11,
                            color: const Color(0xFF6B5F4D),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (item.userStory.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          '"${item.userStory}"',
                          style: GoogleFonts.notoSans(
                            fontSize: 10.5,
                            color: const Color(0xFF888888),
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
