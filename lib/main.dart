import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:collection';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';

// --- 전역 오디오 플레이어 ---
final AudioPlayer bgmPlayer = AudioPlayer();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBqdPjDzJJcSZYsem9sbZZY_Gf9TMAXm0o",
        appId: "1:749732944978:android:4d1f1f81da6621b19c138b",
        messagingSenderId: "749732944978",
        projectId: "somindoyoonapp",
        storageBucket: "somindoyoonapp.firebasestorage.app",
      ),
    );
    debugPrint("🔥 Firebase 연결 성공!");
  } catch (e) {
    debugPrint("Firebase 초기화 에러: $e");
  }

  // 배경음악 설정 (재생은 첫 화면 클릭 시 시작되도록 변경 - 웹 자동재생 방지)
  bgmPlayer.setReleaseMode(ReleaseMode.loop);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MiroEscapeApp());
}

class MiroEscapeApp extends StatelessWidget {
  const MiroEscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '픽셀 미로 탈출 3D',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const GameLoader(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- 💡 이미지 리소스 로더 ---
class GameImages {
  static ui.Image? doImage;
  static ui.Image? soImage;
  static ui.Image? c1Image;
  static ui.Image? c2Image;
  static ui.Image? bodyImage;
  static ui.Image? floorImage;
  static ui.Image? tileBrown;
  static ui.Image? tileGray;
  static ui.Image? tileBlack;

  static Future<void> load() async {
    doImage = await _tryLoad('assets/do.png');
    soImage = await _tryLoad('assets/so.png');
    c1Image = await _tryLoad('assets/c1.png');
    c2Image = await _tryLoad('assets/c2.png');
    bodyImage = await _tryLoad('assets/body.png');
    floorImage = await _tryLoad('assets/miro_floor.png');
    tileBrown = await _tryLoad('assets/tile_brown.png');
    tileGray = await _tryLoad('assets/tile_gray.png');
    tileBlack = await _tryLoad('assets/tile_black.png');
  }

  static Future<ui.Image?> _tryLoad(String path) async {
    try {
      final ByteData data = await rootBundle.load(path);
      final Completer<ui.Image> completer = Completer();
      ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image img) {
        completer.complete(img);
      });
      return await completer.future;
    } catch (e) {
      debugPrint("이미지 로딩 실패 (무시됨): $path");
      return null;
    }
  }
}

class GameLoader extends StatefulWidget {
  const GameLoader({super.key});
  @override
  State<GameLoader> createState() => _GameLoaderState();
}

class _GameLoaderState extends State<GameLoader> {
  bool _imagesLoaded = false;

  @override
  void initState() {
    super.initState();
    GameImages.load().then((_) {
      setState(() => _imagesLoaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_imagesLoaded) {
      return const Scaffold(
        body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.cyanAccent),
                SizedBox(height: 20),
                Text("3D 미로 리소스를 불러오는 중...", style: TextStyle(color: Colors.white)),
              ],
            )
        ),
      );
    }
    return LoginScreen();
  }
}

// --- 공통 데이터 ---
enum MiroDifficulty { easy, normal, hard, extreme }

class PlayerDef {
  final String name;
  final String faceAsset;
  PlayerDef({required this.name, required this.faceAsset});
}

class Position {
  final int row;
  final int col;
  Position(this.row, this.col);

  @override
  bool operator ==(Object other) => other is Position && other.row == row && other.col == col;
  @override
  int get hashCode => Object.hash(row, col);
}

class Tile {
  final bool isWall;
  final bool isSafeZone;
  final bool isFinish;
  Tile({this.isWall = false, this.isSafeZone = false, this.isFinish = false});
}

class MiroStyle {
  final MiroDifficulty difficulty;
  final Color floorTint;
  final Color wallFallbackColor;
  final ui.Image? wallTexture;
  final double tileSize;
  final double viewDistance;
  final double wallHeight;

  MiroStyle({
    required this.difficulty,
    required this.floorTint,
    required this.wallFallbackColor,
    this.wallTexture,
    required this.tileSize,
    required this.viewDistance,
    required this.wallHeight,
  });
}

class MiroDefinition {
  final int stageIndex;
  final MiroStyle style;
  final List<List<Tile>> board;
  final Position startPos;
  final Position finishPos;
  final List<Position> safeZones;
  final double monsterSpeedMult;

  MiroDefinition({
    required this.stageIndex,
    required this.style,
    required this.board,
    required this.startPos,
    required this.finishPos,
    required this.safeZones,
    required this.monsterSpeedMult,
  });
}

class MiroGenerator {
  static MiroDefinition generate(MiroDifficulty difficulty, int stageIndex) {
    int width, height;
    double monsterSpeedMult;
    MiroStyle style;

    final random = Random();

    switch (difficulty) {
      case MiroDifficulty.easy:
        width = 15; height = 15;
        monsterSpeedMult = 0.7; // 플레이어 속도 -20%
        style = MiroStyle(
          difficulty: difficulty,
          floorTint: Colors.green[900]!.withOpacity(0.3),
          wallFallbackColor: const Color(0xFF6D4C41),
          wallTexture: GameImages.tileBrown,
          tileSize: 60.0,
          wallHeight: 26.0,
          viewDistance: 9.0, // 시야 2배 확대
        );
        break;
      case MiroDifficulty.normal:
        width = 21; height = 21;
        monsterSpeedMult = 0.8; // 플레이어 속도 -10%
        style = MiroStyle(
          difficulty: difficulty,
          floorTint: Colors.blueGrey[900]!.withOpacity(0.4),
          wallFallbackColor: const Color(0xFF455A64),
          wallTexture: GameImages.tileGray,
          tileSize: 50.0,
          wallHeight: 23.0,
          viewDistance: 9.0, // 시야 2배 확대
        );
        break;
      case MiroDifficulty.hard:
        width = 31; height = 31;
        monsterSpeedMult = 0.9; // 플레이어 속도 동일
        style = MiroStyle(
          difficulty: difficulty,
          floorTint: Colors.deepOrange[900]!.withOpacity(0.2),
          wallFallbackColor: const Color(0xFF212121),
          wallTexture: GameImages.tileBlack,
          tileSize: 45.0,
          wallHeight: 20.0,
          viewDistance: 9.0, // 시야 2배 확대
        );
        break;
      case MiroDifficulty.extreme:
        width = 41; height = 41;
        monsterSpeedMult = 1; // 플레이어 속도 +5%
        style = MiroStyle(
          difficulty: difficulty,
          floorTint: Colors.black.withOpacity(0.5),
          wallFallbackColor: const Color(0xFF000000),
          wallTexture: GameImages.tileBlack,
          tileSize: 40.0,
          wallHeight: 23.0,
          viewDistance: 9.0, // 시야 2배 확대
        );
        break;
    }

    List<List<Tile>> board = List.generate(height, (_) => List.generate(width, (_) => Tile(isWall: true)));

    List<Position> stack = [];
    Position startPos = Position(1, 1);
    board[startPos.row][startPos.col] = Tile(isWall: false);
    stack.add(startPos);

    Position current = startPos;
    List<List<int>> visited = List.generate(height, (_) => List.generate(width, (_) => 0));
    visited[startPos.row][startPos.col] = 1;

    while (stack.isNotEmpty) {
      current = stack.last;
      List<Position> neighbors = [];

      int r = current.row; int c = current.col;
      if (r > 2 && visited[r - 2][c] == 0) neighbors.add(Position(r - 2, c));
      if (r < height - 3 && visited[r + 2][c] == 0) neighbors.add(Position(r + 2, c));
      if (c > 2 && visited[r][c - 2] == 0) neighbors.add(Position(r, c - 2));
      if (c < width - 3 && visited[r][c + 2] == 0) neighbors.add(Position(r, c + 2));

      if (neighbors.isNotEmpty) {
        Position next = neighbors[random.nextInt(neighbors.length)];
        visited[next.row][next.col] = 1;
        visited[(current.row + next.row) ~/ 2][(current.col + next.col) ~/ 2] = 1;

        board[next.row][next.col] = Tile(isWall: false);
        board[(current.row + next.row) ~/ 2][(current.col + next.col) ~/ 2] = Tile(isWall: false);
        stack.add(next);
      } else {
        stack.removeLast();
      }
    }

    Position finishPos = Position(height - 2, width - 2);
    board[finishPos.row][finishPos.col] = Tile(isWall: false, isFinish: true);

    // 💡 [수정] 4분면 안전지대 균등 분배 로직
    int safeZonesPerQuadrant;
    switch (difficulty) {
      case MiroDifficulty.easy:
        safeZonesPerQuadrant = 2; // 각 2개씩 (총 8개)
        break;
      case MiroDifficulty.normal:
        safeZonesPerQuadrant = 3; // 각 3개씩 (총 12개)
        break;
      case MiroDifficulty.hard:
        safeZonesPerQuadrant = 4; // 각 4개씩 (총 16개)
        break;
      case MiroDifficulty.extreme:
        safeZonesPerQuadrant = 6; // 각 6개씩 (총 24개)
        break;
    }

    List<Position> safeZones = [];
    int midRow = height ~/ 2;
    int midCol = width ~/ 2;

    // 특정 구역(사분면)에 안전지대를 배치하는 헬퍼 함수
    void _placeSafeZonesInQuadrant(int minR, int maxR, int minC, int maxC) {
      int count = 0;
      int attempts = 0;
      List<Position> placedZones = [];

      // 구역 내에서 타일들이 뭉치지 않도록 넓이 기반 최소 거리를 계산
      double minDist = sqrt(((maxR - minR) * (maxC - minC)) / safeZonesPerQuadrant) * 0.5;

      while (count < safeZonesPerQuadrant && attempts < 300) {
        attempts++;
        int r = minR + random.nextInt(maxR - minR + 1);
        int c = minC + random.nextInt(maxC - minC + 1);

        // 특정 벽에 배치: 주변 길(wall==false)이 정확히 1개인 벽(막힌 벽)에만 배치
        if (board[r][c].isWall && !board[r][c].isSafeZone) {
          int pathNeighbors = 0;
          if (r - 1 > 0 && !board[r - 1][c].isWall) pathNeighbors++;
          if (r + 1 < height - 1 && !board[r + 1][c].isWall) pathNeighbors++;
          if (c - 1 > 0 && !board[r][c - 1].isWall) pathNeighbors++;
          if (c + 1 < width - 1 && !board[r][c + 1].isWall) pathNeighbors++;

          if (pathNeighbors == 1) {
            bool tooClose = false;
            // 시도 횟수가 적을 때는 거리를 빡빡하게 검사하여 최대한 퍼뜨림
            if (attempts < 150) {
              for (var zone in placedZones) {
                double dist = sqrt(pow(zone.row - r, 2) + pow(zone.col - c, 2));
                if (dist < minDist) {
                  tooClose = true;
                  break;
                }
              }
            }

            if (!tooClose) {
              Position newZone = Position(r, c);
              safeZones.add(newZone);
              placedZones.add(newZone);
              board[r][c] = Tile(isWall: true, isSafeZone: true);
              count++;
            }
          }
        }
      }
    }

    // 1사분면 (좌상단)
    _placeSafeZonesInQuadrant(1, midRow - 1, 1, midCol - 1);
    // 2사분면 (좌하단)
    _placeSafeZonesInQuadrant(midRow, height - 2, 1, midCol - 1);
    // 3사분면 (우상단)
    _placeSafeZonesInQuadrant(1, midRow - 1, midCol, width - 2);
    // 4사분면 (우하단)
    _placeSafeZonesInQuadrant(midRow, height - 2, midCol, width - 2);

    return MiroDefinition(
      stageIndex: stageIndex,
      style: style,
      board: board,
      startPos: startPos,
      finishPos: finishPos,
      safeZones: safeZones,
      monsterSpeedMult: monsterSpeedMult,
    );
  }
}

final List<PlayerDef> availableCharacters = [
  PlayerDef(name: "도윤", faceAsset: "assets/do.png"),
  PlayerDef(name: "소민", faceAsset: "assets/so.png"),
  PlayerDef(name: "윤오", faceAsset: "assets/c1.png"),
  PlayerDef(name: "윤성", faceAsset: "assets/c2.png"),
];

// --- 1. 로그인 화면 ---
class LoginScreen extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  String playerId = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("미로 탈출", style: TextStyle(color: Colors.cyanAccent, fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 50),
              TextField(
                controller: _idController,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: "아이디 입력",
                  hintStyle: const TextStyle(color: Colors.white24),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.blueGrey, width: 2), borderRadius: BorderRadius.circular(15)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.cyanAccent, width: 2), borderRadius: BorderRadius.circular(15)),
                ),
                onChanged: (value) => setState(() => playerId = value.trim()),
              ),
              const SizedBox(height: 30),
              if (playerId.isNotEmpty)
                ElevatedButton(
                  onPressed: () async {
                    // 유저 상호작용 후 사운드 재생 (특히 웹 환경의 경우 필수)
                    if (bgmPlayer.state != PlayerState.playing) {
                      await bgmPlayer.play(AssetSource('audio/bgm.wav'));
                    }
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CharacterSelectScreen(playerId: playerId)));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("다음", style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 2. 캐릭터 선택 화면 ---
class CharacterSelectScreen extends StatefulWidget {
  final String playerId;
  const CharacterSelectScreen({required this.playerId});

  @override
  State<CharacterSelectScreen> createState() => _CharacterSelectScreenState();
}

class _CharacterSelectScreenState extends State<CharacterSelectScreen> {
  int selectedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("${widget.playerId}님, 캐릭터 선택", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: availableCharacters.asMap().entries.map((e) {
                int idx = e.key;
                PlayerDef p = e.value;
                bool isSelected = selectedIndex == idx;
                return GestureDetector(
                  onTap: () => setState(() => selectedIndex = idx),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    width: 120,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.cyanAccent.withOpacity(0.2) : Colors.white10,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white24, width: 3),
                    ),
                    child: Column(
                      children: [
                        Image.asset(p.faceAsset, width: 80, height: 80, errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 80, color: Colors.grey)),
                        const SizedBox(height: 10),
                        Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 50),
            if (selectedIndex != -1)
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ControlSelectScreen(playerId: widget.playerId, selectedCharacterIndex: selectedIndex)));
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text("선택 완료", style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}

// --- 2-5. 조작 방식 선택 화면 ---
class ControlSelectScreen extends StatelessWidget {
  final String playerId;
  final int selectedCharacterIndex;

  const ControlSelectScreen({required this.playerId, required this.selectedCharacterIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("조작 방식을 선택하세요", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModeBtn(context, Icons.gamepad, "방식 1", "가운데 십자 조작", 1),
                const SizedBox(width: 30),
                _buildModeBtn(context, Icons.swipe, "방식 2", "양손 와이드 조작", 2),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildModeBtn(BuildContext context, IconData icon, String title, String desc, int mode) {
    return GestureDetector(
      onTap: () {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => MiroSelectScreen(playerId: playerId, selectedCharacterIndex: selectedCharacterIndex, controlMode: mode)));
      },
      child: Container(
        width: 140, height: 160,
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.cyanAccent, width: 3)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.cyanAccent, size: 60),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// --- 3. 미로 선택 화면 ---
class MiroSelectScreen extends StatefulWidget {
  final String playerId;
  final int selectedCharacterIndex;
  final int controlMode;

  const MiroSelectScreen({required this.playerId, required this.selectedCharacterIndex, required this.controlMode});

  @override
  State<MiroSelectScreen> createState() => _MiroSelectScreenState();
}

class _MiroSelectScreenState extends State<MiroSelectScreen> {
  bool isTestMode = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("미로 스테이지 선택", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            SingleChildScrollView(
              child: Column(
                children: MiroDifficulty.values.map((difficulty) => _buildDifficultySection(context, difficulty)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultySection(BuildContext context, MiroDifficulty difficulty) {
    String diffName; Color diffColor; int stageCount;
    switch (difficulty) {
      case MiroDifficulty.easy: diffName = "쉬움"; diffColor = Colors.greenAccent; stageCount = 5; break;
      case MiroDifficulty.normal: diffName = "보통"; diffColor = Colors.blueAccent; stageCount = 5; break;
      case MiroDifficulty.hard: diffName = "어려움"; diffColor = Colors.orangeAccent; stageCount = 3; break;
      case MiroDifficulty.extreme: diffName = "극악"; diffColor = Colors.redAccent; stageCount = 2; break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Text(diffName, style: TextStyle(color: diffColor, fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(stageCount, (index) => ElevatedButton(
              onPressed: () => _startMiro(context, difficulty, index + 1),
              style: ElevatedButton.styleFrom(backgroundColor: isTestMode ? diffColor : Colors.grey[700], minimumSize: const Size(60, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text("${index + 1}", style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold)),
            )),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _startMiro(BuildContext context, MiroDifficulty difficulty, int stageIndex) {
    if (Firebase.apps.isNotEmpty) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => GameplayScreen(
        playerId: widget.playerId,
        selectedCharacterIndex: widget.selectedCharacterIndex,
        difficulty: difficulty,
        stageIndex: stageIndex,
        controlMode: widget.controlMode,
      )));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Firebase 초기화 중입니다. 잠시 후 다시 시도해주세요.")));
    }
  }
}

// --- 4. 메인 게임플레이 화면 ---
class GameplayScreen extends StatefulWidget {
  final String playerId;
  final int selectedCharacterIndex;
  final MiroDifficulty difficulty;
  final int stageIndex;
  final int controlMode;

  const GameplayScreen({required this.playerId, required this.selectedCharacterIndex, required this.difficulty, required this.stageIndex, required this.controlMode});

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  late MiroDefinition miroDef;

  late Position playerPos;
  double playerVisualRow = 1.0;
  double playerVisualCol = 1.0;

  Position? monsterPos;
  double? monsterVisualRow;
  double? monsterVisualCol;

  Stopwatch stopwatch = Stopwatch();
  late Timer gameLoopTimer;
  Timer? monsterSpawnTimer;

  // 💡 버튼 꾹 누르기 타이머
  Timer? moveTimer;

  bool isMonsterSpawned = false;
  bool isGameOver = false;
  bool isEscaped = false;
  bool isPaused = false;

  int safeZoneCounter = 0;
  Timer? safeZoneTimer;

  int hintCount = 3;
  List<Position> hintTrail = [];
  Timer? hintFadeTimer;

  int minimapCount = 3;

  late int monsterSpeedMs;
  final FocusNode _focusNode = FocusNode();
  final Random random = Random();

  ui.Image? playerFace;
  List<ui.Image?> monsterFaces = [];

  @override
  void initState() {
    super.initState();
    miroDef = MiroGenerator.generate(widget.difficulty, widget.stageIndex);
    playerPos = miroDef.startPos;
    playerVisualRow = playerPos.row.toDouble();
    playerVisualCol = playerPos.col.toDouble();

    monsterSpeedMs = (150 / miroDef.monsterSpeedMult).toInt();

    _assignFaces();

    stopwatch.start();
    gameLoopTimer = Timer.periodic(const Duration(milliseconds: 16), _gameLoop);
    monsterSpawnTimer = Timer.periodic(const Duration(seconds: 2), (t) => _checkMonsterSpawn());
  }

  void _assignFaces() {
    if (widget.selectedCharacterIndex == 0) playerFace = GameImages.doImage;
    else if (widget.selectedCharacterIndex == 1) playerFace = GameImages.soImage;
    else if (widget.selectedCharacterIndex == 2) playerFace = GameImages.c1Image;
    else playerFace = GameImages.c2Image;

    if (widget.selectedCharacterIndex != 0) monsterFaces.add(GameImages.doImage);
    if (widget.selectedCharacterIndex != 1) monsterFaces.add(GameImages.soImage);
    if (widget.selectedCharacterIndex != 2) monsterFaces.add(GameImages.c1Image);
    if (widget.selectedCharacterIndex != 3) monsterFaces.add(GameImages.c2Image);
  }

  @override
  void dispose() {
    stopwatch.stop();
    gameLoopTimer.cancel();
    monsterSpawnTimer?.cancel();
    safeZoneTimer?.cancel();
    hintFadeTimer?.cancel();
    moveTimer?.cancel(); // 💡 타이머 정리
    _focusNode.dispose();
    super.dispose();
  }

  void _togglePause() {
    focusNode: _focusNode.requestFocus();
    if (isGameOver || isEscaped) return;
    setState(() {
      isPaused = !isPaused;
      if (isPaused) {
        stopwatch.stop();
        _stopContinuousMove(); // 이동 정지
      } else {
        stopwatch.start();
      }
    });
  }

  void _gameLoop(Timer t) {
    if (isGameOver || isEscaped || isPaused) return;

    setState(() {
      playerVisualRow += (playerPos.row - playerVisualRow) * 0.25;
      playerVisualCol += (playerPos.col - playerVisualCol) * 0.25;

      if (monsterPos != null) {
        monsterVisualRow ??= monsterPos!.row.toDouble();
        monsterVisualCol ??= monsterPos!.col.toDouble();
        monsterVisualRow = monsterVisualRow! + (monsterPos!.row - monsterVisualRow!) * 0.15;
        monsterVisualCol = monsterVisualCol! + (monsterPos!.col - monsterVisualCol!) * 0.15;
      }

      if (playerPos == miroDef.finishPos) {
        _escpaeSuccess();
        return;
      }

      bool inSafeZone = miroDef.board[playerPos.row][playerPos.col].isSafeZone;
      if (isMonsterSpawned && inSafeZone) {
        if (safeZoneTimer == null || !safeZoneTimer!.isActive) {
          safeZoneCounter = 3;
          safeZoneTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) { timer.cancel(); return; }
            setState(() {
              if (safeZoneCounter > 1) {
                safeZoneCounter--;
              } else {
                isMonsterSpawned = false;
                monsterPos = null;
                monsterVisualRow = null;
                monsterVisualCol = null;
                safeZoneCounter = 0;
                timer.cancel();
                bgmPlayer.play(AssetSource('audio/bgm.wav')); // 💡 몬스터 소멸 시 기존 BGM으로 복귀
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("괴물이 포기하고 사라졌습니다!"), duration: Duration(seconds: 1)));
              }
            });
          });
        }
      } else {
        if (safeZoneTimer != null && safeZoneTimer!.isActive) {
          safeZoneTimer!.cancel();
          safeZoneCounter = 0;
        }
      }

      if (isMonsterSpawned && monsterPos != null) {
        _moveMonster();
        if (monsterPos == playerPos && !inSafeZone) {
          _gameOver();
        }
      }
    });
  }

  int monsterMoveTick = 0;
  void _moveMonster() {
    monsterMoveTick += 16;
    if (monsterMoveTick < monsterSpeedMs) return;
    monsterMoveTick = 0;

    int targetRow = playerPos.row; int targetCol = playerPos.col;
    int curRow = monsterPos!.row; int curCol = monsterPos!.col;

    Queue<List<Position>> queue = Queue<List<Position>>();
    Set<Position> visited = {};

    queue.add([Position(curRow, curCol)]);
    visited.add(Position(curRow, curCol));

    List<Position>? path;

    while (queue.isNotEmpty) {
      List<Position> currentPath = queue.removeFirst();
      Position current = currentPath.last;

      if (current.row == targetRow && current.col == targetCol) {
        path = currentPath;
        break;
      }

      List<Position> neighbors = [
        Position(current.row - 1, current.col),
        Position(current.row + 1, current.col),
        Position(current.row, current.col - 1),
        Position(current.row, current.col + 1),
      ];

      for (Position neighbor in neighbors) {
        if (!_isWall(neighbor.row, neighbor.col) && !visited.contains(neighbor)) {
          visited.add(neighbor);
          List<Position> newPath = List.from(currentPath)..add(neighbor);
          queue.add(newPath);
        }
      }
    }

    if (path != null && path.length > 1) {
      Position nextPos = path[1];
      if (!miroDef.board[nextPos.row][nextPos.col].isSafeZone) {
        monsterPos = nextPos;
      }
    }
  }

  void _checkMonsterSpawn() {
    if (isPaused || isGameOver || isEscaped) return;
    if (!isMonsterSpawned && random.nextDouble() < 0.10) {
      setState(() {
        isMonsterSpawned = true;

        // BFS를 사용하여 길 기준 이동 거리(Depth) 계산
        List<Position> candidates = [];
        Queue<Position> queue = Queue();
        Set<Position> visited = {};
        Map<Position, int> distances = {};

        queue.add(playerPos);
        visited.add(playerPos);
        distances[playerPos] = 0;

        int targetDist = 30;

        while (queue.isNotEmpty) {
          Position curr = queue.removeFirst();
          int dist = distances[curr]!;

          if (dist >= targetDist - 5 && dist <= targetDist + 5 && !miroDef.board[curr.row][curr.col].isSafeZone) {
             candidates.add(curr);
          }

          if (dist > targetDist + 5) continue;

          List<Position> neighbors = [
            Position(curr.row - 1, curr.col),
            Position(curr.row + 1, curr.col),
            Position(curr.row, curr.col - 1),
            Position(curr.row, curr.col + 1),
          ];

          for (Position n in neighbors) {
            if (!_isWall(n.row, n.col) && !visited.contains(n)) {
              visited.add(n);
              distances[n] = dist + 1;
              queue.add(n);
            }
          }
        }

        if (candidates.isEmpty) {
           // 목표 거리 영역에 타일이 없다면, 가장 먼 거리의 타일을 후보로 사용
           int maxDist = 0;
           distances.forEach((k, v) {
             if (v > maxDist && !miroDef.board[k.row][k.col].isSafeZone) maxDist = v;
           });
           distances.forEach((k, v) {
             if (v >= maxDist - 2 && !miroDef.board[k.row][k.col].isSafeZone) candidates.add(k);
           });
        }

        if (candidates.isNotEmpty) {
           monsterPos = candidates[random.nextInt(candidates.length)];
           monsterVisualRow = monsterPos!.row.toDouble();
           monsterVisualCol = monsterPos!.col.toDouble();
        } else {
           // 만약을 위한 백폴
           monsterPos = Position(1, 1);
        }

        // 💡 몬스터 소환 시 긴장감 있는 BGM 재생
        bgmPlayer.play(AssetSource('audio/monster_bgm.wav'));

        debugPrint("⚠️ 몬스터 소환! (이동 거리 30칸 근처)");
      });
    }
  }

  bool _isWall(int r, int c) {
    if (r < 0 || r >= miroDef.board.length || c < 0 || c >= miroDef.board[0].length) return true;
    if (miroDef.board[r][c].isSafeZone) return false;
    return miroDef.board[r][c].isWall;
  }

  void _movePlayer(int dr, int dc) {
    if (isGameOver || isEscaped || isPaused) return;
    int nr = playerPos.row + dr; int nc = playerPos.col + dc;
    if (!_isWall(nr, nc)) {
      setState(() {
        playerPos = Position(nr, nc);
      });
    }
  }

  // 💡 [추가] 연속 이동 제어 로직
  void _startContinuousMove(int dr, int dc) {
    _movePlayer(dr, dc); // 터치 즉시 1칸 이동
    moveTimer?.cancel();
    moveTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      _movePlayer(dr, dc);
    });
  }

  void _stopContinuousMove() {
    moveTimer?.cancel();
  }

  void _useHint() {
    if (hintCount <= 0 || isGameOver || isEscaped) return;
    setState(() { hintCount--; });

    Queue<List<Position>> queue = Queue<List<Position>>();
    Set<Position> visited = {};

    queue.add([Position(playerPos.row, playerPos.col)]);
    visited.add(Position(playerPos.row, playerPos.col));

    List<Position>? path;

    while (queue.isNotEmpty) {
      List<Position> currentPath = queue.removeFirst();
      Position current = currentPath.last;

      if (current == miroDef.finishPos) {
        path = currentPath;
        break;
      }

      List<Position> neighbors = [
        Position(current.row - 1, current.col),
        Position(current.row + 1, current.col),
        Position(current.row, current.col - 1),
        Position(current.row, current.col + 1),
      ];

      for (Position neighbor in neighbors) {
        if (!_isWall(neighbor.row, neighbor.col) && !visited.contains(neighbor)) {
          visited.add(neighbor);
          List<Position> newPath = List.from(currentPath)..add(neighbor);
          queue.add(newPath);
        }
      }
    }

    if (path != null) {
      setState(() {
        hintTrail = path!;
        hintFadeTimer?.cancel();
        hintFadeTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() { hintTrail.clear(); });
        });
      });
    }
  }

  void _showMinimap() {
    if (minimapCount <= 0 || isGameOver || isEscaped) return;
    setState(() { minimapCount--; });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("미니맵", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(
            painter: MinimapPainter(miroDef: miroDef, playerPos: playerPos, monsterPos: monsterPos),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            child: const Text("닫기", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _gameOver() {
    if (isGameOver) return;
    bgmPlayer.play(AssetSource('audio/bgm.wav')); // 💡 원래 음악으로 복귀
    setState(() {
      isGameOver = true;
      stopwatch.stop();
      _stopContinuousMove(); // 게임오버 시 이동 정지
      _showGameOverDialog();
    });
  }

  void _escpaeSuccess() {
    if (isEscaped) return;
    bgmPlayer.play(AssetSource('audio/bgm.wav')); // 💡 탈출 성공 시 원래 음악으로 복귀
    setState(() {
      isEscaped = true;
      stopwatch.stop();
      _stopContinuousMove(); // 탈출 시 이동 정지
      double finalTime = stopwatch.elapsedMilliseconds / 1000.0;
      _saveScoreAndRanking(finalTime);
    });
  }

  Future<void> _saveScoreAndRanking(double finalTime) async {
    CollectionReference miroScores = FirebaseFirestore.instance.collection('miro_scores');
    String difficultyName;
    switch (widget.difficulty) {
      case MiroDifficulty.easy: difficultyName = "쉬움"; break;
      case MiroDifficulty.normal: difficultyName = "보통"; break;
      case MiroDifficulty.hard: difficultyName = "어려움"; break;
      case MiroDifficulty.extreme: difficultyName = "극악"; break;
    }

    await miroScores.add({
      'difficulty': difficultyName,
      'stage': widget.stageIndex,
      'playerId': widget.playerId,
      'escapeTime': finalTime,
      'timestamp': FieldValue.serverTimestamp(),
    }).then((value) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => RankingScreen(playerId: widget.playerId, finishedScoreDoc: value)));
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 저장 중 오류가 발생했습니다.")));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => RankingScreen(playerId: widget.playerId)));
    });
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("GAME OVER", textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 3)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bug_report, size: 80, color: Colors.redAccent),
            SizedBox(height: 10),
            Text("몬스터에게 잡혔습니다!", style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => MiroSelectScreen(playerId: widget.playerId, selectedCharacterIndex: widget.selectedCharacterIndex, controlMode: widget.controlMode))); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            child: const Text("다시 하기", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => RankingScreen(playerId: widget.playerId))); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            child: const Text("랭킹 보기", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CharacterSelectScreen(playerId: widget.playerId))); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            child: const Text("처음으로", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double redOpacity = 0.0;
    if (isMonsterSpawned && !isGameOver) {
      int cycle = stopwatch.elapsedMilliseconds % 3000;
      if (cycle < 1000) {
        redOpacity = (cycle / 1000.0) * 0.25;
      } else if (cycle < 2000) {
        redOpacity = ((2000 - cycle) / 1000.0) * 0.25;
      } else {
        redOpacity = 0.0;
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (isPaused) return KeyEventResult.ignored;
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.keyW) _movePlayer(-1, 0);
              else if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.keyS) _movePlayer(1, 0);
              else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.keyA) _movePlayer(0, -1);
              else if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.keyD) _movePlayer(0, 1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${widget.playerId}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                          Text("STAGE ${widget.stageIndex}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          StreamBuilder(
                            stream: Stream.periodic(const Duration(milliseconds: 100)),
                            builder: (_, __) => Text("${(stopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(1)}s", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 5),
                          IconButton(
                            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.cyanAccent),
                            onPressed: _togglePause,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: _useHint,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(color: hintCount > 0 ? Colors.yellow.withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: hintCount > 0 ? Colors.yellow : Colors.white24)),
                              child: Row(
                                children: [
                                  Icon(Icons.search, color: hintCount > 0 ? Colors.yellow : Colors.white54, size: 20),
                                  const SizedBox(width: 4),
                                  Text("$hintCount", style: TextStyle(color: hintCount > 0 ? Colors.yellow : Colors.white54, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _showMinimap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(color: minimapCount > 0 ? Colors.cyanAccent.withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: minimapCount > 0 ? Colors.cyanAccent : Colors.white24)),
                              child: Row(
                                children: [
                                  Icon(Icons.map, color: minimapCount > 0 ? Colors.cyanAccent : Colors.white54, size: 20),
                                  const SizedBox(width: 4),
                                  Text("$minimapCount", style: TextStyle(color: minimapCount > 0 ? Colors.cyanAccent : Colors.white54, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: Colors.black,
                        child: ClipRect(
                          child: CustomPaint(
                            painter: Miro3DPainter(
                              playerFace: playerFace,
                              monsterFaces: monsterFaces,
                              miroDef: miroDef,
                              playerVisualRow: playerVisualRow,
                              playerVisualCol: playerVisualCol,
                              monsterVisualRow: monsterVisualRow,
                              monsterVisualCol: monsterVisualCol,
                              floorImage: GameImages.floorImage,
                              bodyImage: GameImages.bodyImage,
                              hintTrail: hintTrail,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isMonsterSpawned)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(color: Colors.redAccent.withOpacity(redOpacity)),
                        ),
                      ),
                    if (safeZoneCounter > 0)
                      Center(
                        child: Text(
                            "$safeZoneCounter",
                            style: TextStyle(color: Colors.cyanAccent.withOpacity(0.8), fontSize: 120, fontWeight: FontWeight.bold)
                        ),
                      ),
                    if (isPaused)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black87,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("PAUSE", style: TextStyle(color: Colors.cyanAccent, fontSize: 50, fontWeight: FontWeight.bold, letterSpacing: 5)),
                                const SizedBox(height: 30),
                                IconButton(
                                  iconSize: 80,
                                  icon: const Icon(Icons.play_circle_fill, color: Colors.white),
                                  onPressed: _togglePause,
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              if (widget.controlMode == 1)
                Container(
                  padding: const EdgeInsets.all(20.0),
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      children: [
                        _buildDpadBtn(Icons.arrow_drop_up, -1, 0, size: 75),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildDpadBtn(Icons.arrow_left, 0, -1, size: 75),
                            const SizedBox(width: 75),
                            _buildDpadBtn(Icons.arrow_right, 0, 1, size: 75),
                          ],
                        ),
                        const SizedBox(height: 5),
                        _buildDpadBtn(Icons.arrow_drop_down, 1, 0, size: 75),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                  color: Colors.black87,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _buildDpadBtn(Icons.arrow_back_ios_new, 0, -1, size: 65),
                          const SizedBox(width: 10),
                          _buildDpadBtn(Icons.arrow_forward_ios, 0, 1, size: 65),
                        ],
                      ),
                      Row(
                        children: [
                          _buildDpadBtn(Icons.keyboard_arrow_up, -1, 0, size: 65),
                          const SizedBox(width: 10),
                          _buildDpadBtn(Icons.keyboard_arrow_down, 1, 0, size: 65),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 💡 [수정] 꾹 눌렀을 때 연속 이동을 지원하는 커스텀 버튼
  Widget _buildDpadBtn(IconData i, int dr, int dc, {double size = 70}) => GestureDetector(
    onTapDown: (_) => _startContinuousMove(dr, dc),
    onTapUp: (_) => _stopContinuousMove(),
    onTapCancel: () => _stopContinuousMove(),
    child: Container(
      width: size, height: size - 10,
      decoration: BoxDecoration(
          color: Colors.cyanAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2)
      ),
      child: Center(child: Icon(i, color: Colors.cyanAccent, size: size * 0.6)),
    ),
  );
}

// --- 💡 3D 입체 미로 페인터 ---
class Miro3DPainter extends CustomPainter {
  final ui.Image? playerFace;
  final List<ui.Image?> monsterFaces;
  final ui.Image? floorImage;
  final ui.Image? bodyImage;
  final MiroDefinition miroDef;
  final List<Position> hintTrail;

  final double playerVisualRow;
  final double playerVisualCol;
  final double? monsterVisualRow;
  final double? monsterVisualCol;

  Miro3DPainter({
    required this.playerFace,
    required this.monsterFaces,
    required this.miroDef,
    required this.playerVisualRow,
    required this.playerVisualCol,
    this.monsterVisualRow,
    this.monsterVisualCol,
    this.floorImage,
    this.bodyImage,
    required this.hintTrail,
  });

  @override
  void paint(Canvas canvas, Size size) {
    List<List<Tile>> board = miroDef.board;
    int height = board.length;
    int width = board[0].length;

    double tileSize = miroDef.style.tileSize;
    double wallH = miroDef.style.wallHeight;

    double px = (playerVisualCol + 0.5) * tileSize;
    double py = (playerVisualRow + 0.5) * tileSize;
    double zoom = 0.9; // 기존 1.8에서 0.9로 축소하여 약 2배 더 넓은 범위 표시

    canvas.save();
    canvas.translate(size.width / 2 - px * zoom, size.height / 2 - py * zoom);
    canvas.scale(zoom, zoom);

    Paint tileBgPaint = Paint()..color = Colors.grey[900]!;
    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        Rect destRect = Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize);
        if (floorImage != null) {
          canvas.drawImageRect(
              floorImage!,
              Rect.fromLTWH(0, 0, floorImage!.width.toDouble(), floorImage!.height.toDouble()),
              destRect,
              Paint()
          );
        } else {
          canvas.drawRect(destRect, tileBgPaint);
        }
      }
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, width * tileSize, height * tileSize), Paint()..color = miroDef.style.floorTint);

    Paint dropShadowPaint = Paint()..color = Colors.black.withOpacity(0.85);
    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        if (board[r][c].isWall || board[r][c].isSafeZone) {
          canvas.drawRect(Rect.fromLTWH(c * tileSize + 10, r * tileSize + 10, tileSize, tileSize), dropShadowPaint);
        }
      }
    }

    if (hintTrail.isNotEmpty) {
      Paint hintPaint = Paint()..color = Colors.yellowAccent.withOpacity(0.5)..style = PaintingStyle.fill;
      for (Position p in hintTrail) {
        canvas.drawCircle(Offset((p.col + 0.5) * tileSize, (p.row + 0.5) * tileSize), tileSize * 0.2, hintPaint);
      }
    }

    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        if (board[r][c].isFinish) {
          canvas.drawRect(Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize), Paint()..color = Colors.cyanAccent.withOpacity(0.6));
        }
      }
    }

    Paint safeZoneWallPaint = Paint()..color = Colors.blueAccent.withOpacity(0.6);
    Paint wallBorderPaint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 1.5;

    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        Tile t = board[r][c];
        double x = c * tileSize;
        double y = r * tileSize;

        if (t.isSafeZone) {
          Rect frontRect = Rect.fromLTWH(x, y - (wallH * 0.5) + tileSize, tileSize, wallH * 0.5);
          canvas.drawRect(frontRect, safeZoneWallPaint);
          canvas.drawRect(frontRect, wallBorderPaint);

          Rect topRect = Rect.fromLTWH(x, y - (wallH * 0.5), tileSize, tileSize);
          canvas.drawRect(topRect, safeZoneWallPaint);
          canvas.drawRect(topRect, wallBorderPaint);

        } else if (t.isWall) {
          Rect frontRect = Rect.fromLTWH(x, y - wallH + tileSize, tileSize, wallH);
          if (miroDef.style.wallTexture != null) {
            canvas.drawImageRect(
                miroDef.style.wallTexture!,
                Rect.fromLTWH(0, 0, miroDef.style.wallTexture!.width.toDouble(), miroDef.style.wallTexture!.height.toDouble()),
                frontRect,
                Paint()
            );
            canvas.drawRect(frontRect, Paint()..color = Colors.black.withOpacity(0.6));
          } else {
            canvas.drawRect(frontRect, Paint()..color = _darken(miroDef.style.wallFallbackColor, 0.4));
          }
          canvas.drawRect(frontRect, wallBorderPaint);

          Rect topRect = Rect.fromLTWH(x, y - wallH, tileSize, tileSize);
          if (miroDef.style.wallTexture != null) {
            canvas.drawImageRect(
                miroDef.style.wallTexture!,
                Rect.fromLTWH(0, 0, miroDef.style.wallTexture!.width.toDouble(), miroDef.style.wallTexture!.height.toDouble()),
                topRect,
                Paint()
            );
            canvas.drawRect(topRect, Paint()..color = Colors.black.withOpacity(0.1));
          } else {
            canvas.drawRect(topRect, Paint()..color = miroDef.style.wallFallbackColor);
          }
          canvas.drawRect(topRect, wallBorderPaint);
        }
      }

      if (playerVisualRow.round() == r) {
        bool inSafeZone = board[playerVisualRow.round()][playerVisualCol.round()].isSafeZone;
        _drawCharacter(canvas, playerVisualCol * tileSize, playerVisualRow * tileSize, tileSize, playerFace, inSafeZone);
      }

      if (monsterVisualRow != null && monsterVisualRow!.round() == r) {
        _drawMonster(canvas, monsterVisualCol! * tileSize, monsterVisualRow! * tileSize, tileSize);
      }
    }

    canvas.restore();

    double viewRadius = miroDef.style.viewDistance * tileSize * zoom;
    Paint fogPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        viewRadius,
        [Colors.transparent, Colors.black87, Colors.black],
        [0.4, 0.8, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fogPaint);
  }

  Color _darken(Color c, [double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(c);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

  void _drawCharacter(Canvas canvas, double x, double y, double tileSize, ui.Image? face, bool isHidden) {
    double size = tileSize * 0.8;
    double cx = x + tileSize / 2;
    double cy = y + tileSize / 2 - size * 0.3;

    Paint p = Paint()..color = Colors.white.withOpacity(isHidden ? 0.4 : 1.0);

    if (bodyImage != null) {
      canvas.drawImageRect(bodyImage!, Rect.fromLTWH(0, 0, bodyImage!.width.toDouble(), bodyImage!.height.toDouble()), Rect.fromLTWH(cx - size*0.4, cy - size*0.1, size*0.8, size*0.8), p);
    } else {
      canvas.drawRect(Rect.fromLTWH(cx - size*0.2, cy, size*0.4, size*0.5), Paint()..color = Colors.blueAccent.withOpacity(isHidden ? 0.4 : 1.0));
    }

    if (face != null) {
      canvas.drawImageRect(face, Rect.fromLTWH(0, 0, face.width.toDouble(), face.height.toDouble()), Rect.fromLTWH(cx - size*0.4, cy - size*0.7, size*0.8, size*0.8), p);
    } else {
      canvas.drawCircle(Offset(cx, cy - size*0.3), size*0.3, Paint()..color = Colors.yellowAccent.withOpacity(isHidden ? 0.4 : 1.0));
    }
  }

  void _drawMonster(Canvas canvas, double x, double y, double tileSize) {
    double size = tileSize * 0.8;
    double cx = x + tileSize / 2;
    double cy = y + tileSize / 2 - size * 0.2;

    Paint legPaint = Paint()..color = Colors.redAccent.shade700..strokeWidth = 3.0..style = PaintingStyle.stroke;
    for (int i = 0; i < 8; i++) {
      double angle = i * (pi / 4);
      canvas.drawLine(Offset(cx, cy), Offset(cx + cos(angle)*size*0.7, cy + sin(angle)*size*0.7), legPaint);
    }

    canvas.drawCircle(Offset(cx, cy), size * 0.4, Paint()..color = Colors.black87);

    if (monsterFaces.isNotEmpty) {
      ui.Image mFace = monsterFaces[DateTime.now().millisecondsSinceEpoch % monsterFaces.length]!;
      canvas.save();
      Paint p = Paint()..colorFilter = const ColorFilter.mode(Colors.redAccent, BlendMode.modulate);
      canvas.drawImageRect(mFace, Rect.fromLTWH(0, 0, mFace.width.toDouble(), mFace.height.toDouble()), Rect.fromLTWH(cx - size*0.3, cy - size*0.3, size*0.6, size*0.6), p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

// --- 미니맵 팝업용 페인터 ---
class MinimapPainter extends CustomPainter {
  final MiroDefinition miroDef;
  final Position playerPos;
  final Position? monsterPos;

  MinimapPainter({required this.miroDef, required this.playerPos, this.monsterPos});

  @override
  void paint(Canvas canvas, Size size) {
    int height = miroDef.board.length;
    int width = miroDef.board[0].length;
    double tileSize = size.width / width;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black54);

    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        Tile t = miroDef.board[r][c];
        Rect rect = Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize);

        if (t.isSafeZone) {
          canvas.drawRect(rect, Paint()..color = Colors.blueAccent.withOpacity(0.8));
        } else if (t.isWall) {
          canvas.drawRect(rect, Paint()..color = Colors.white24);
        } else if (t.isFinish) {
          canvas.drawRect(rect, Paint()..color = Colors.cyanAccent);
        } else {
          canvas.drawRect(rect, Paint()..color = Colors.black87);
        }
      }
    }

    // 도착지 표시 (도착지 위치 계산)
    canvas.drawCircle(Offset((miroDef.finishPos.col + 0.5) * tileSize, (miroDef.finishPos.row + 0.5) * tileSize), tileSize * 0.4, Paint()..color = Colors.yellowAccent);

    // 플레이어 표시
    canvas.drawCircle(Offset((playerPos.col + 0.5) * tileSize, (playerPos.row + 0.5) * tileSize), tileSize * 0.6, Paint()..color = Colors.greenAccent);

    // 몬스터 표시
    if (monsterPos != null) {
      canvas.drawCircle(Offset((monsterPos!.col + 0.5) * tileSize, (monsterPos!.row + 0.5) * tileSize), tileSize * 0.5, Paint()..color = Colors.redAccent);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

// --- 5. 랭킹 등록 및 확인 화면 ---
class RankingScreen extends StatefulWidget {
  final String playerId;
  final DocumentReference? finishedScoreDoc;

  const RankingScreen({required this.playerId, this.finishedScoreDoc});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final CollectionReference miroScores = FirebaseFirestore.instance.collection('miro_scores');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("🏆 랭킹 TOP 10 🏆", style: TextStyle(color: Colors.cyanAccent, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 30),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: miroScores.orderBy('escapeTime').limit(10).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Text("데이터를 불러오지 못했습니다.", style: TextStyle(color: Colors.redAccent));
                    if (snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator(color: Colors.cyanAccent);

                    final data = snapshot.data!;
                    return ListView.separated(
                      itemCount: data.docs.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12, thickness: 1),
                      itemBuilder: (context, index) {
                        var doc = data.docs[index];
                        String diff = doc['difficulty'];
                        int stage = doc['stage'];
                        String id = doc['playerId'];
                        double time = doc['escapeTime'];

                        bool isMyFinishedScore = (widget.finishedScoreDoc != null && widget.finishedScoreDoc!.id == doc.id);

                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                          decoration: isMyFinishedScore ? BoxDecoration(color: Colors.cyanAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.cyanAccent)) : null,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("#${index + 1}", style: TextStyle(color: isMyFinishedScore ? Colors.cyanAccent : Colors.grey[600], fontSize: 24, fontWeight: FontWeight.bold)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(id, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text("$diff 스테이지: $stage", style: const TextStyle(color: Colors.white60, fontSize: 14)),
                                ],
                              ),
                              Text("${time.toStringAsFixed(1)}초", style: TextStyle(color: isMyFinishedScore ? Colors.cyanAccent : Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen())); },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800], padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text("처음으로", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


