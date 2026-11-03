import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/scent_labels.dart';

// ==========================================
// 향 노트 피라미드 (TOP / HEART / BASE) + 주요 향 계열 순위
// - 노트가 층별로 공개되지 않은 향수는 노트 목록 또는 향 계열만 표시
// - 예전 기록(층별 데이터 없음)은 한 줄 노트 문자열로 표시
// ==========================================
class NotePyramid extends StatelessWidget {
  final Map<String, dynamic> perfume;
  final bool compact;

  const NotePyramid({super.key, required this.perfume, this.compact = false});

  List<String> _list(String key) => List<String>.from(perfume[key] ?? []);

  @override
  Widget build(BuildContext context) {
    final top = _list('top_notes');
    final middle = _list('middle_notes');
    final base = _list('base_notes');
    final flat = _list('notes');
    final accords = _list('accords');
    final hasLayers = top.isNotEmpty || middle.isNotEmpty || base.isNotEmpty;
    final legacyText = (perfume['scent_notes'] ?? '').toString();

    final children = <Widget>[];
    if (hasLayers) {
      final layers = [
        ('TOP', '뿌린 직후 ~15분, 처음 맡는 향', top),
        ('HEART', '30분 ~ 2시간, 향의 중심', middle),
        ('BASE', '몇 시간 뒤까지 남는 잔향', base),
      ].where((l) => l.$3.isNotEmpty).toList();
      for (var i = 0; i < layers.length; i++) {
        if (i > 0) {
          children.add(const Divider(height: 18, color: Color(0xFFE8E3D8)));
        }
        children.add(_layer(layers[i].$1, compact ? null : layers[i].$2, layers[i].$3));
      }
    } else if (flat.isNotEmpty) {
      children.add(_layer('NOTES', compact ? null : '층 구분 없이 공개된 노트', flat));
    } else if (legacyText.isNotEmpty && !legacyText.startsWith('Main Accords')) {
      children.add(Text(legacyText,
          style: GoogleFonts.notoSans(
              fontSize: 12.5, height: 1.45, color: const Color(0xFF5E5446))));
    }

    if (accords.isNotEmpty) {
      children.add(Padding(
        padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12),
        child: _accordRank(accords, showHint: !hasLayers && flat.isEmpty),
      ));
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E3D8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _layer(String title, String? hint, List<String> notes) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(title,
              style: GoogleFonts.cormorantGaramond(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: const Color(0xFF8C7B65))),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hint != null) ...[
                Text(hint,
                    style: GoogleFonts.notoSans(
                        fontSize: 10.5, color: const Color(0xFF9A9184))),
                const SizedBox(height: 6),
              ],
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: notes.map(_chip).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String note) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E0D4)),
      ),
      child: Text(noteLabel(note),
          style: GoogleFonts.notoSans(
              fontSize: compact ? 11 : 11.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF4A443C))),
    );
  }

  Widget _accordRank(List<String> accords, {required bool showHint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(showHint ? '주요 향 계열 (노트 미공개 향수)' : '주요 향 계열',
            style: GoogleFonts.notoSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF8C7B65))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: accords.asMap().entries.map((e) {
            return Text('${e.key + 1}  ${accordLabel(e.value)}',
                style: GoogleFonts.notoSans(
                    fontSize: 12,
                    fontWeight: e.key == 0 ? FontWeight.w700 : FontWeight.w500,
                    color: e.key == 0 ? const Color(0xFF2B2824) : const Color(0xFF6B6357)));
          }).toList(),
        ),
      ],
    );
  }
}

// Fragrantica 상세 페이지로 이동하는 버튼 (DB에 링크가 있는 향수에만 표시)
class FragranticaLinkButton extends StatelessWidget {
  final String url;

  const FragranticaLinkButton({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6B5F4D),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () async {
        final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('링크를 열 수 없습니다.'), behavior: SnackBarBehavior.floating),
          );
        }
      },
      icon: const Icon(Icons.open_in_new, size: 15),
      label: Text('Fragrantica에서 자세히 보기',
          style: GoogleFonts.notoSans(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
