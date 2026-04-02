import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const PangGameApp());
}

class PangGameApp extends StatelessWidget {
  const PangGameApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '라스트팡 for Kids',
      theme: ThemeData(primarySwatch: Colors.orange),
      home: const GameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 게임에 사용할 귀여운 아이콘과 색상 조합 (이미지 파일 대체)
class BlockType {
  final IconData icon;
  final Color color;
  BlockType(this.icon, this.color);
}

final List<BlockType> blockTypes = [
  BlockType(Icons.favorite, Colors.redAccent), // 하트
  BlockType(Icons.star, Colors.amber),         // 별
  BlockType(Icons.apple, Colors.green),        // 사과
  BlockType(Icons.water_drop, Colors.blue),    // 물방울
  BlockType(Icons.pets, Colors.brown),         // 강아지 발바닥
];

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const int rows = 8;
  static const int cols = 7;

  List<List<BlockType?>> grid = [];
  int score = 0;
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    _initializeBoard();
  }

  // 보드 초기화
  void _initializeBoard() {
    grid = List.generate(
      rows,
      (i) => List.generate(cols, (j) => blockTypes[random.nextInt(blockTypes.length)]),
    );
    score = 0;
    setState(() {});
  }

  // 블록 터치 시 로직 (Flood Fill 알고리즘으로 연결된 블록 찾기)
  void _onBlockTapped(int row, int col) {
    if (grid[row][col] == null) return;

    BlockType targetType = grid[row][col]!;
    Set<String> matchedBlocks = {};

    void findMatches(int r, int c) {
      if (r < 0 || r >= rows || c < 0 || c >= cols) return;
      if (grid[r][c] != targetType) return;

      String key = '$r,$c';
      if (matchedBlocks.contains(key)) return;

      matchedBlocks.add(key);

      findMatches(r + 1, c);
      findMatches(r - 1, c);
      findMatches(r, c + 1);
      findMatches(r, c - 1);
    }

    findMatches(row, col);

    // 2개 이상 연결되어 있을 때만 터짐
    if (matchedBlocks.length >= 2) {
      setState(() {
        // 1. 점수 추가 (많이 터뜨릴수록 보너스)
        score += (matchedBlocks.length * 10) + ((matchedBlocks.length - 2) * 5);

        // 2. 터진 자리 비우기
        for (String key in matchedBlocks) {
          List<String> parts = key.split(',');
          grid[int.parse(parts[0])][int.parse(parts[1])] = null;
        }

        // 3. 중력 적용 (위에 있는 블록 아래로 떨어뜨리기)
        _applyGravity();
      });
    }
  }

  // 빈 공간으로 블록 떨어뜨리고 새 블록 채우기
  void _applyGravity() {
    for (int c = 0; c < cols; c++) {
      int emptySpaces = 0;
      for (int r = rows - 1; r >= 0; r--) {
        if (grid[r][c] == null) {
          emptySpaces++;
        } else if (emptySpaces > 0) {
          grid[r + emptySpaces][c] = grid[r][c];
          grid[r][c] = null;
        }
      }
      // 맨 위에 생긴 빈 공간에 새 블록 랜덤 생성
      for (int r = 0; r < emptySpaces; r++) {
        grid[r][c] = blockTypes[random.nextInt(blockTypes.length)];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange[50], // 부드러운 배경색
      appBar: AppBar(
        title: Text('점수: $score', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        centerTitle: true,
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeBoard,
            tooltip: '새 게임',
          )
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: cols / rows,
          child: Container(
            margin: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)
              ],
            ),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 1.0,
              ),
              itemCount: rows * cols,
              itemBuilder: (context, index) {
                int row = index ~/ cols;
                int col = index % cols;
                BlockType? block = grid[row][col];

                return GestureDetector(
                  onTap: () => _onBlockTapped(row, col),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.all(4.0),
                    decoration: BoxDecoration(
                      color: block?.color ?? Colors.transparent,
                      shape: BoxShape.circle,
                      boxShadow: block != null ? [
                        BoxShadow(color: Colors.black26, offset: const Offset(2, 2), blurRadius: 4)
                      ] : [],
                    ),
                    child: block != null
                        ? Icon(block.icon, color: Colors.white, size: 32)
                        : const SizedBox.shrink(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}