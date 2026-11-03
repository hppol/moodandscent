import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/scent_store.dart';

// 👍/👎/♡ 버튼 줄 (상태를 Firestore에서 불러와 표시) - 검색·상세 화면 공용
class ReactionBar extends StatefulWidget {
  final Map<String, dynamic> perfume;

  const ReactionBar({super.key, required this.perfume});

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  int _vote = 0;
  bool _wished = false;

  @override
  void initState() {
    super.initState();
    final id = widget.perfume['id'] as String? ?? '';
    Future.wait([ScentStore.getVote(id), ScentStore.isWished(id)]).then((r) {
      if (mounted) {
        setState(() {
          _vote = r[0] as int;
          _wished = r[1] as bool;
        });
      }
    });
  }

  Widget _button(IconData icon, String label, bool active, Color color, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: active ? color : const Color(0xFF6B6357),
          backgroundColor: active ? color.withOpacity(0.1) : Colors.white,
          side: BorderSide(color: active ? color : const Color(0xFFE6E0D4)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: GoogleFonts.notoSans(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Future<void> _setVote(int v) async {
    final next = _vote == v ? 0 : v;
    setState(() => _vote = next);
    await ScentStore.setVote(widget.perfume, next);
  }

  Future<void> _toggleWish() async {
    setState(() => _wished = !_wished);
    await ScentStore.setWished(widget.perfume, _wished);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _button(_vote == 1 ? Icons.thumb_up : Icons.thumb_up_outlined, '좋아요', _vote == 1,
            const Color(0xFF5E7A55), () => _setVote(1)),
        const SizedBox(width: 8),
        _button(_vote == -1 ? Icons.thumb_down : Icons.thumb_down_outlined, '별로예요', _vote == -1,
            const Color(0xFF9A5B4F), () => _setVote(-1)),
        const SizedBox(width: 8),
        _button(_wished ? Icons.favorite : Icons.favorite_border, '위시', _wished,
            const Color(0xFFB0605F), _toggleWish),
      ],
    );
  }
}
