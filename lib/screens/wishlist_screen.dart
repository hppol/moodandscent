import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/scent_store.dart';
import 'perfume_detail_screen.dart';
import 'search_screen.dart';

// 위시리스트: 결과 화면에서 ♡를 누른 향수 모음 (Firestore 'wishlist')
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ScentStore.getWishlist();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _remove(Map<String, dynamic> perfume) async {
    await ScentStore.setWished(perfume, false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          'MY WISHLIST',
          style: GoogleFonts.cormorantGaramond(
            letterSpacing: 3.5,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF1E1E1E),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 22, color: Color(0xFF222222)),
            tooltip: '향수 검색해서 담기',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
              _load();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF8C7B65)))
          : _items.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final perfume =
                        Map<String, dynamic>.from(_items[i]['perfume'] ?? {});
                    return _buildCard(perfume);
                  },
                ),
    );
  }

  // 브랜드·이름만 보여주고, 누르면 상세 화면(노트·비슷한 향수·나와의 기록·Fragrantica 링크)
  Widget _buildCard(Map<String, dynamic> perfume) {
    final isLuxury = perfume['tier'] == 'luxury';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PerfumeDetailScreen(perfume: perfume)),
        );
        _load(); // 상세 화면에서 ♡를 해제했을 수 있음
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECE7DE)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isLuxury ? '👑' : '🌿'}  ${(perfume['brand'] ?? '').toString().toUpperCase()}',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                      color: const Color(0xFF8C7B65),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    perfume['name'] ?? '',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F1F1F),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.favorite, size: 20, color: Color(0xFFB0605F)),
              tooltip: '위시리스트에서 빼기',
              onPressed: () => _remove(perfume),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFB5AC9E)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border,
                size: 46, color: Color(0xFFC9BBA4)),
            const SizedBox(height: 14),
            Text(
              '아직 담은 향수가 없습니다',
              style: GoogleFonts.notoSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3B352D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '추천 결과나 🔍 향수 검색에서 ♡ 위시 버튼을 눌러 사고 싶은 향수를 모아보세요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSans(
                fontSize: 12.5,
                color: const Color(0xFF8C8374),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
