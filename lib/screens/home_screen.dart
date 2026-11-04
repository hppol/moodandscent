import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/curation_history.dart';
import 'history_screen.dart';
import 'insights_screen.dart';
import 'result_screen.dart';
import 'search_screen.dart';
import 'wear_calendar_view.dart';
import 'wishlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = image.name;
      });
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
    });
  }

  /// quick=false: 사진 + 글로 추천(/analyze), quick=true: 사진 없이 글만으로 빠른 추천(/quick)
  /// scope='mine': 내 향수(위시리스트·좋아요·착용 기록) 안에서만 추천
  Future<void> _requestCuration({bool quick = false, String scope = 'all'}) async {
    if (!quick && _selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('오늘의 OOTD(착장) 사진을 먼저 올려주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('오늘의 일상, TPO 또는 원하시는 향을 편하게 적어주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$kApiBaseUrl/${quick ? 'quick' : 'analyze'}'),
      );

      if (quick) {
        request.fields['scope'] = scope;
      } else {
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          _selectedImageBytes!,
          filename: _selectedImageName ?? 'ootd.jpg',
        ));
      }

      request.fields['mood_text'] = _textController.text;

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = jsonDecode(utf8.decode(response.bodyBytes));

        if (data['status'] == 'success') {
          // 듀오 추천 데이터 추출 (향수 정보는 서버 DB 값만 사용, 앱에서 임의로 채우지 않음)
          final luxury = data['luxury_perfume'];
          final affordable = data['affordable_perfume'];
          if (luxury == null || affordable == null) {
            throw Exception('추천 결과가 비어 있습니다.');
          }
          final visualized = data['visualized_ingredients'] ?? '향조 오브제';
          final tpo = data['tpo_analysis'] ?? '';
          final base64Img = data['generated_image_base64'] ?? '';
          final weatherBadge = data['weather_badge'] ?? 'MOKPO 24°C · 구름 조금';
          final killingQuote = data['killing_quote'] ?? '오늘의 시그니처 향기';
          final userOotdBase64 = !quick && _selectedImageBytes != null ? base64Encode(_selectedImageBytes!) : '';

          // [내 향수 서랍]에 자동 영구 보관!
          final now = DateTime.now();
          final dateStr =
              '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';

          final historyItem = CurationHistoryItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            date: dateStr,
            userStory: _textController.text.trim(),
            weatherBadge: weatherBadge,
            killingQuote: killingQuote,
            userOotdBase64: userOotdBase64,
            luxuryPerfume: Map<String, dynamic>.from(luxury),
            affordablePerfume: Map<String, dynamic>.from(affordable),
            visualizedIngredients: visualized,
            tpoAnalysis: tpo,
            base64Image: base64Img,
          );
          final saved = await CurationHistoryItem.saveHistory(historyItem);
          if (!saved && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('진열장 저장에 실패했습니다. 인터넷 연결을 확인해 주세요.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          if (mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ResultScreen(
                  luxuryPerfume: Map<String, dynamic>.from(luxury),
                  affordablePerfume: Map<String, dynamic>.from(affordable),
                  visualizedIngredients: visualized,
                  tpoAnalysis: tpo,
                  base64Image: base64Img,
                  weatherBadge: weatherBadge,
                  killingQuote: killingQuote,
                  userOotdBase64: userOotdBase64,
                  historyId: historyItem.id,
                  historyDate: historyItem.date,
                  userStory: historyItem.userStory,
                  tabLabels: scope == 'mine'
                      ? const ['🎯 오늘의 픽', '🔁 다른 선택지']
                      : const ['👑 럭셔리 니치 픽', '🌿 가성비 데일리 대안'],
                ),
              ),
            );

            // 결과 화면에서 뒤로 나오면(화살표든 버튼이든) 사진과 텍스트를 깨끗하게 자동 초기화!
            if (mounted) {
              setState(() {
                _selectedImageBytes = null;
                _selectedImageName = null;
                _textController.clear();
              });
            }
          }
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('진단 중 오류가 발생했습니다: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
          icon: const Icon(Icons.insights, color: Color(0xFF222222), size: 23),
          tooltip: '취향 리포트 · AI 검증 로그',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InsightsScreen()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined,
                color: Color(0xFF222222), size: 22),
            tooltip: '착용 캘린더',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WearCalendarScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border,
                color: Color(0xFF222222), size: 22),
            tooltip: '위시리스트',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WishlistScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.shelves, color: Color(0xFF222222), size: 23),
            tooltip: '내 향수 서랍',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        title: Column(
          children: [
            Text(
              'ATELIER DE PARFUM',
              style: GoogleFonts.cormorantGaramond(
                letterSpacing: 4.0,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: const Color(0xFF9E8A68),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'MOOD & SCENT',
              style: GoogleFonts.cormorantGaramond(
                letterSpacing: 2.5,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: const Color(0xFF1F1F1F),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // 헤더 타이틀 및 설명
              Center(
                child: Text(
                  'Signature Scent Curation',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF222222),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '착장의 무드와 오늘의 일상(TPO)에 딱 맞는 니치 향수를 디자인합니다.',
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    color: const Color(0xFF757575),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 18),

              // 향수 검색 (검색창 모양 버튼 → 검색 화면)
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SearchScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE6E0D4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 19, color: Color(0xFF8C7B65)),
                      const SizedBox(width: 10),
                      Text(
                        '향수 이름이나 브랜드로 찾아보기',
                        style: GoogleFonts.notoSans(
                            fontSize: 13, color: const Color(0xFFA39A8C)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // -------------------------------------------------------------
              // 1. OOTD 이미지 업로드 카드 (사진 잘림 없이 100% 원본 비율 보존!)
              // -------------------------------------------------------------
              _selectedImageBytes == null
                  ? GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 280,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFE5E2DC),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFF7F5F0),
                              ),
                              child: const Icon(
                                Icons.photo_library_outlined,
                                size: 36,
                                color: Color(0xFF8C7B65),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              '오늘의 OOTD 사진 업로드',
                              style: GoogleFonts.notoSans(
                                color: const Color(0xFF2B2B2B),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '터치하여 전신 또는 상의 착장 사진을 선택하세요\n(머리부터 발끝까지 잘리지 않고 온전히 담깁니다)',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSans(
                                color: const Color(0xFF9E9E9E),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        Container(
                          constraints: const BoxConstraints(
                            minHeight: 280,
                            maxHeight: 440,
                          ),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E), // 세련된 갤러리 백드롭
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            // BoxFit.contain을 적용하여 전신 사진도 절대 잘리지 않음!
                            child: Image.memory(
                              _selectedImageBytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        // 우측 상단 플로팅 컨트롤 (다시 선택 / 삭제)
                        Positioned(
                          top: 14,
                          right: 14,
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.3)),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.crop_original,
                                          size: 15, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text(
                                        '사진 변경',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _clearImage,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.3)),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

              const SizedBox(height: 28),

              // -------------------------------------------------------------
              // 2. 자유로운 이야기 입력 섹션 (일상, TPO, 위로, 원하는 분위기)
              // -------------------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '당신의 오늘 이야기 (Story & Mood)',
                    style: GoogleFonts.notoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2F2F2F),
                    ),
                  ),
                  Text(
                    '자유로운 문장 가능',
                    style: GoogleFonts.notoSans(
                      fontSize: 12,
                      color: const Color(0xFF9E8A68),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '어디를 가는지, 어떤 하루를 보냈는지, 풍기고 싶은 분위기까지 무엇이든 적어주세요.',
                style: GoogleFonts.notoSans(
                  fontSize: 12,
                  color: const Color(0xFF888888),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              // 세련된 텍스트필드
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _textController,
                  minLines: 4,
                  maxLines: 6,
                  style: GoogleFonts.notoSans(
                    fontSize: 14,
                    height: 1.55,
                    color: const Color(0xFF262626),
                  ),
                  decoration: InputDecoration(
                    hintText:
                        '무엇이든 자유롭게 들려주세요.\n\n• "오늘 하루 종일 일하느라 지쳤는데, 나를 따뜻하게 위로해 줄 포근한 향 없을까?"\n• "소개팅 나가는데 너무 뻔하지 않으면서 은근히 기억에 남는 분위기 연출해 줘."\n• "강의실에서 수업 들어. 튀지 않고 단정한 비누나 은은한 우디 계열 원해."\n• "작년에 갔던 비 내리는 숲길 냄새나 헌책방 같은 아날로그 감성 향수 찾아줘."',
                    hintStyle: GoogleFonts.notoSans(
                      fontSize: 12.5,
                      height: 1.5,
                      color: const Color(0xFFAFAFAF),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE8E5DF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE8E5DF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                          color: Color(0xFF9E8A68), width: 1.5),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // -------------------------------------------------------------
              // 3. 큐레이션 실행 버튼
              // -------------------------------------------------------------
              ElevatedButton(
                onPressed: _isLoading ? null : () => _requestCuration(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1E1E),
                  foregroundColor: const Color(0xFFFAF7F2),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFE8DCC4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'AI 조향사가 착장과 TPO를 분석 중입니다...',
                            style: GoogleFonts.notoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFE8DCC4),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 18, color: Color(0xFFD4AF37)),
                          const SizedBox(width: 10),
                          Text(
                            'Find My Signature Scent',
                            style: GoogleFonts.cormorantGaramond(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 12),

              // ⚡ 사진 없이 빠른 추천
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _showQuickSheet,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF3B352D),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFDED8CE)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.bolt, size: 19, color: Color(0xFF8C7B65)),
                label: Text(
                  '사진 없이 빠른 추천',
                  style: GoogleFonts.notoSans(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 빠른 추천 범위 선택: 전체 DB / 내 향수 안에서
  void _showQuickSheet() {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('빠른 추천도 오늘의 일정이나 원하는 분위기를 한 줄 적어주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Widget option(IconData icon, String title, String desc, String scope) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(context);
          _requestCuration(quick: true, scope: scope);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6E0D4)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF8C7B65)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.notoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1F1F1F))),
                    const SizedBox(height: 2),
                    Text(desc,
                        style: GoogleFonts.notoSans(
                            fontSize: 12, color: const Color(0xFF8C8374))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF9F8F6),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('⚡ 빠른 추천',
                style: GoogleFonts.notoSans(
                    fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('사진 없이 오늘의 글과 날씨만으로 추천해요.',
                style: GoogleFonts.notoSans(
                    fontSize: 12.5, color: const Color(0xFF8C8374))),
            const SizedBox(height: 16),
            option(Icons.travel_explore, '전체 향수 DB에서',
                '1,000개 중에서 니치 픽 + 가성비 대안 추천', 'all'),
            const SizedBox(height: 10),
            option(Icons.inventory_2_outlined, '내 향수 안에서',
                '위시리스트·좋아요·착용 기록 향수 중 오늘 뿌릴 향수 고르기', 'mine'),
          ],
        ),
      ),
    );
  }
}
