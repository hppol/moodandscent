import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../utils/scent_labels.dart';
import 'perfume_detail_screen.dart';

// ==========================================
// 향수 검색: 향수 DB(1,000개)에서 이름·브랜드로 찾기 (AI 없음)
// - 일반 모드: 👍/👎/♡ 반응 남기기
// - pickMode: 착용 캘린더에 직접 기록할 향수를 골라 돌려줌
// ==========================================
class SearchScreen extends StatefulWidget {
  final bool pickMode;

  const SearchScreen({super.key, this.pickMode = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  Future<void> _search(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$kApiBaseUrl/perfumes/search')
          .replace(queryParameters: {'q': query, 'limit': '30'});
      final res = await http.get(uri);
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (!mounted || _controller.text != query) return;
      setState(() {
        _results = List<Map<String, dynamic>>.from(data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'AI 서버에 연결할 수 없습니다. 서버가 켜져 있는지 확인해 주세요.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF222222)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.pickMode ? '뿌린 향수 찾기' : 'FIND A SCENT',
          style: widget.pickMode
              ? GoogleFonts.notoSans(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1E1E1E))
              : GoogleFonts.cormorantGaramond(
                  letterSpacing: 3.5, fontWeight: FontWeight.w800, fontSize: 17, color: const Color(0xFF1E1E1E)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: '향수 이름이나 브랜드 (예: santal, le labo, 바카라는 baccarat)',
                hintStyle: GoogleFonts.notoSans(fontSize: 13, color: const Color(0xFFA39A8C)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8C7B65)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE6E0D4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE6E0D4)),
                ),
              ),
            ),
          ),
          if (_controller.text.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('리뷰가 많은 인기 향수',
                    style: GoogleFonts.notoSans(fontSize: 11.5, color: const Color(0xFF8C8374))),
              ),
            ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _isLoading && _results.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF8C7B65)))
                    : _results.isEmpty
                        ? Center(
                            child: Text('검색 결과가 없어요. 영어 이름으로 검색해 보세요.',
                                style: GoogleFonts.notoSans(fontSize: 13, color: const Color(0xFF8C8374))),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                            itemCount: _results.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _resultTile(_results[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _resultTile(Map<String, dynamic> p) {
    final accords = List<String>.from(p['accords'] ?? []);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openDetail(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFECE7DE)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((p['brand'] ?? '').toString().toUpperCase(),
                      style: GoogleFonts.cormorantGaramond(
                          fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 2, color: const Color(0xFF8C7B65))),
                  Text(p['name'] ?? '',
                      style: GoogleFonts.notoSans(
                          fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1F1F1F))),
                  const SizedBox(height: 3),
                  Text(accords.take(3).map(accordLabel).join(' · '),
                      style: GoogleFonts.notoSans(fontSize: 11.5, color: const Color(0xFF8C8374))),
                ],
              ),
            ),
            Text(p['tier'] == 'luxury' ? '👑' : '🌿', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Color(0xFFB5AC9E)),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> p) async {
    final picked = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => PerfumeDetailScreen(perfume: p, pickMode: widget.pickMode)),
    );
    // 착용 기록용으로 고른 향수는 캘린더로 돌려줌
    if (picked != null && widget.pickMode && mounted) Navigator.pop(context, picked);
  }
}
