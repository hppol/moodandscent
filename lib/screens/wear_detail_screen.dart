import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/curation_history.dart';
import '../widgets/note_pyramid.dart';
import '../widgets/photo_viewer.dart';
import 'perfume_detail_screen.dart';

// ==========================================
// 착용 기록 자세히 보기: 그날의 착장(원본 비율) · 내가 쓴 글 · 그날 AI가 쓴 향수 설명 · 노트
// history가 없으면(검색으로 직접 기록한 날) 향수 정보만 보여줌
// ==========================================
class WearDetailScreen extends StatelessWidget {
  final String dateLabel;
  final Map<String, dynamic> entry;
  final CurationHistoryItem? history;

  const WearDetailScreen({
    super.key,
    required this.dateLabel,
    required this.entry,
    this.history,
  });

  @override
  Widget build(BuildContext context) {
    final perfume = Map<String, dynamic>.from(entry['perfume'] ?? {});
    final h = history;
    // 그날 추천 카드에서 AI가 쓴 설명 (고른 향수가 럭셔리/가성비 중 어느 쪽인지 찾아서)
    Map<String, dynamic> card = {};
    if (h != null) {
      card = h.luxuryPerfume['id'] == perfume['id'] ? h.luxuryPerfume : h.affordablePerfume;
    }
    final photo = (entry['ootdThumb'] ?? '') as String;
    final story = ((entry['userStory'] ?? '') as String).isNotEmpty
        ? entry['userStory'] as String
        : (h?.userStory ?? '');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF222222)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('$dateLabel 착용 기록',
            style: GoogleFonts.notoSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E1E1E))),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
        children: [
          // 1. 그날의 착장 + 내가 쓴 글
          if (photo.isNotEmpty) ...[
            TapToZoomPhoto(base64Image: photo, maxHeight: 260),
            const SizedBox(height: 6),
            Center(
              child: Text('사진을 누르면 크게 볼 수 있어요',
                  style: GoogleFonts.notoSans(fontSize: 10.5, color: const Color(0xFFA39A8C))),
            ),
            const SizedBox(height: 14),
          ],
          if (story.isNotEmpty)
            Text('"$story"',
                textAlign: photo.isNotEmpty ? TextAlign.center : TextAlign.start,
                style: GoogleFonts.notoSans(fontSize: 13.5, height: 1.55, color: const Color(0xFF4A443C))),

          // 2. 그날의 카피와 날씨
          if (h != null) ...[
            const SizedBox(height: 14),
            Center(
              child: Text('“${h.killingQuote}”',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 15, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: const Color(0xFF26231F))),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('🌤️ ${h.weatherBadge}',
                  style: GoogleFonts.notoSans(fontSize: 11.5, color: const Color(0xFF8C8374))),
            ),
          ],

          // 3. 뿌린 향수
          const SizedBox(height: 24),
          Text('이날 뿌린 향수',
              style: GoogleFonts.notoSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF8C7B65))),
          const SizedBox(height: 6),
          Text((perfume['brand'] ?? '').toString().toUpperCase(),
              style: GoogleFonts.cormorantGaramond(
                  fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 2.5, color: const Color(0xFF8C7B65))),
          Text(perfume['name'] ?? '',
              style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700, color: const Color(0xFF1F1F1F))),
          if ((card['scent_description_kr'] ?? '').toString().isNotEmpty)
            _textBlock('👃 어떤 냄새인가요?', card['scent_description_kr']),
          if ((card['reason_kr'] ?? '').toString().isNotEmpty)
            _textBlock('🍸 이날의 Vibe Check', card['reason_kr']),
          const SizedBox(height: 14),
          NotePyramid(perfume: perfume, compact: true),
          if (h != null && h.tpoAnalysis.isNotEmpty) _textBlock('🤫 조향사의 귓속말', h.tpoAnalysis),

          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3B352D),
              side: const BorderSide(color: Color(0xFFDED8CE)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PerfumeDetailScreen(perfume: perfume)),
            ),
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('향수 상세 보기 (비슷한 향수 · Fragrantica)'),
          ),
        ],
      ),
    );
  }

  Widget _textBlock(String title, String body) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECE7DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.notoSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF2B2824))),
          const SizedBox(height: 6),
          Text(body, style: GoogleFonts.notoSans(fontSize: 13, height: 1.55, color: const Color(0xFF4A443C))),
        ],
      ),
    );
  }
}
