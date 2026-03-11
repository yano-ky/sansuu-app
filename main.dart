import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const int kMaxMultiNum = 9;
const int kMaxDivNum = 9;

void main() => runApp(const MathApp());

// ── enum ──────────────────────────────────────────────────────────────
enum MathMode {
  plus, minus, multi, div,
  storyPlus, storyMinus, storyMulti, storyDiv,
  puzzle, wrong;

  bool get isPlus  => this == plus  || this == storyPlus;
  bool get isMinus => this == minus || this == storyMinus;
  bool get isMulti => this == multi || this == storyMulti;
  bool get isDiv   => this == div   || this == storyDiv;

  String get label {
    switch (this) {
      case MathMode.plus:       return 'たしざん';
      case MathMode.minus:      return 'ひきざん';
      case MathMode.multi:      return 'かけざん';
      case MathMode.div:        return 'わりざん';
      case MathMode.storyPlus:  return 'たしざん(ぶんしょう)';
      case MathMode.storyMinus: return 'ひきざん(ぶんしょう)';
      case MathMode.storyMulti: return 'かけざん(ぶんしょう)';
      case MathMode.storyDiv:   return 'わりざん(ぶんしょう)';
      case MathMode.puzzle:     return 'パズル';
      case MathMode.wrong:      return 'にがてこくふく';
    }
  }

  static MathMode fromString(String s) => MathMode.values.firstWhere(
    (e) => e.name == s, orElse: () => MathMode.plus);
}

// ── 統計管理 ─────────────────────────────────────────────────────────
class StatsManager {
  static Future<void> record(MathMode mode, bool correct) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'stats_${mode.name}';
    Map<String, dynamic> data = {};
    try { data = json.decode(prefs.getString(key) ?? '{}'); } catch (_) {}
    data['correct'] = ((data['correct'] as int?) ?? 0) + (correct ? 1 : 0);
    data['total']   = ((data['total']   as int?) ?? 0) + 1;
    await prefs.setString(key, json.encode(data));
  }

  static Future<Map<MathMode, Map<String, int>>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <MathMode, Map<String, int>>{};
    for (final mode in MathMode.values) {
      if (mode == MathMode.wrong) continue;
      try {
        final raw = prefs.getString('stats_${mode.name}');
        if (raw != null) {
          final d = json.decode(raw);
          result[mode] = {'correct': (d['correct'] as int?) ?? 0, 'total': (d['total'] as int?) ?? 0};
        }
      } catch (_) {}
    }
    return result;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final mode in MathMode.values) await prefs.remove('stats_${mode.name}');
  }
}

// ── 間違い履歴管理（保護者用・消えない） ─────────────────────────────
class HistoryManager {
  static const _key = 'wrongHistory';

  // 間違えたとき呼ぶ：同じ問題なら missCount を +1、なければ追加
  static Future<void> recordWrong(MathMode mode, int n1, int n2, int target) async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> history = [];
    try { history = json.decode(prefs.getString(_key) ?? '[]'); } catch (_) {}

    final idx = history.indexWhere((q) =>
        q['m'] == mode.name && q['n1'] == n1 && q['n2'] == n2);
    if (idx >= 0) {
      history[idx]['miss'] = ((history[idx]['miss'] as int?) ?? 1) + 1;
    } else {
      history.add({'m': mode.name, 'n1': n1, 'n2': n2, 't': target, 'miss': 1});
    }
    await prefs.setString(_key, json.encode(history));
  }

  static Future<List<Map<String, dynamic>>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return List<Map<String, dynamic>>.from(
          (json.decode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
    } catch (_) { return []; }
  }

  // 確認済みにする（dismissed フラグを立てる）
  static Future<void> dismiss(MathMode mode, int n1, int n2) async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> history = [];
    try { history = json.decode(prefs.getString(_key) ?? '[]'); } catch (_) {}
    final idx = history.indexWhere((q) =>
        q['m'] == mode.name && q['n1'] == n1 && q['n2'] == n2);
    if (idx >= 0) {
      history[idx]['dismissed'] = true;
      await prefs.setString(_key, json.encode(history));
    }
  }

  // 確認済みを除いてロード（保護者ページのサマリー用）
  static Future<List<Map<String, dynamic>>> loadActive() async {
    final all = await loadAll();
    return all.where((q) => q['dismissed'] != true).toList();
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

// ── App ───────────────────────────────────────────────────────────────
class MathApp extends StatelessWidget {
  const MathApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'さんすうアプリ',
    theme: ThemeData(primarySwatch: Colors.orange, useMaterial3: true, fontFamily: 'Hiragino Sans'),
    home: const MenuScreen(),
  );
}

// ── メニュー画面 ──────────────────────────────────────────────────────
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  double maxNum = 10, goal = 10;
  bool isSelect = true;
  List<dynamic> wrongList = [];
  // 表示するメニューのON/OFF（デフォルトは全部表示）
  Set<String> hiddenModes = {};

  @override
  void initState() { super.initState(); _loadSettings(); }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> parsed = [];
    try {
      final s = prefs.getString('wrongList');
      if (s != null) parsed = json.decode(s);
    } catch (_) {}
    setState(() {
      maxNum    = prefs.getDouble('maxNum')  ?? 10;
      goal      = prefs.getDouble('goal')   ?? 10;
      isSelect  = prefs.getBool('isSelect') ?? true;
      wrongList = parsed;
      hiddenModes = (prefs.getStringList('hiddenModes') ?? []).toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('さんすうアプリ'),
        backgroundColor: Colors.orange.shade200,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: 'ほごしゃメニュー',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentPage()));
              _loadSettings();
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.orange.shade50,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (wrongList.isNotEmpty)
                  _menuCard('🔥 にがてを こくふく (${wrongList.length})', Colors.red.shade100, MathMode.wrong),
                if (!hiddenModes.contains('plus'))
                  _menuCard('➕ たしざん (しき)',      Colors.blue.shade100,   MathMode.plus),
                if (!hiddenModes.contains('minus'))
                  _menuCard('➖ ひきざん (しき)',      Colors.green.shade100,  MathMode.minus),
                if (!hiddenModes.contains('multi'))
                  _menuCard('✖ かけざん (しき)',       Colors.purple.shade100, MathMode.multi),
                if (!hiddenModes.contains('div'))
                  _menuCard('➗ わりざん (しき)',      Colors.teal.shade100,   MathMode.div),
                if (!hiddenModes.contains('story'))
                  _menuCard('📖 ぶんしょう もんだい', Colors.orange.shade100, null, isStoryMenu: true),
                if (!hiddenModes.contains('puzzle'))
                  _menuCard('🧩 しきをつくる パズル', Colors.yellow.shade200, null, isPuzzleMenu: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuCard(String title, Color color, MathMode? mode,
      {bool isStoryMenu = false, bool isPuzzleMenu = false}) {
    return Card(
      color: color,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        onTap: () async {
          if (isStoryMenu) {
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => StoryMenuScreen(maxNum: maxNum.toInt(), goal: goal.toInt(), isSelect: isSelect)));
          } else if (isPuzzleMenu) {
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => PuzzleMenuScreen(maxNum: maxNum.toInt(), goal: goal.toInt(), isSelect: isSelect)));
          } else if (mode != null) {
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => MathGame(mode: mode, maxNum: maxNum.toInt(), goal: goal.toInt(), isSelect: isSelect)));
          }
          _loadSettings();
        },
      ),
    );
  }
}

// ── 保護者ページ ──────────────────────────────────────────────────────
class ParentPage extends StatefulWidget {
  const ParentPage({super.key});
  @override State<ParentPage> createState() => _ParentPageState();
}

class _ParentPageState extends State<ParentPage> {
  double maxNum = 10, goal = 10;
  bool isSelect = true;
  Map<MathMode, Map<String, int>> stats = {};
  List<dynamic> wrongList = [];
  List<Map<String, dynamic>> history = [];
  Set<String> hiddenModes = {};
  Set<String> expandedModes = {};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s   = await StatsManager.loadAll();
    final hist = await HistoryManager.loadActive();
    List<dynamic> wl = [];
    try {
      final saved = prefs.getString('wrongList');
      if (saved != null) wl = json.decode(saved);
    } catch (_) {}
    setState(() {
      maxNum    = prefs.getDouble('maxNum')  ?? 10;
      goal      = prefs.getDouble('goal')   ?? 10;
      isSelect  = prefs.getBool('isSelect') ?? true;
      stats     = s;
      wrongList = wl;
      history   = hist;
      hiddenModes = (prefs.getStringList('hiddenModes') ?? []).toSet();
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('maxNum', maxNum);
    await prefs.setDouble('goal', goal);
    await prefs.setBool('isSelect', isSelect);
    await prefs.setStringList('hiddenModes', hiddenModes.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ほごしゃメニュー'),
        backgroundColor: Colors.blueGrey.shade200,
        centerTitle: true,
      ),
      body: Container(
        color: Colors.blueGrey.shade50,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _sectionTitle('📊 せいかいりつ グラフ'),
                _buildStatsChart(),
                const SizedBox(height: 20),
                _sectionTitle('📋 まちがい りれき'),
                _buildWeakList(),
                const SizedBox(height: 20),
                _sectionTitle('👁️ メニューの ひょうじ'),
                _buildVisibilitySettings(),
                const SizedBox(height: 20),
                _sectionTitle('⚙️ もんだい せってい'),
                _buildSettings(),
                const SizedBox(height: 20),
                _buildResetButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
  );

  Widget _buildStatsChart() {
    final modes  = [MathMode.plus, MathMode.minus, MathMode.multi, MathMode.div];
    final labels = ['➕', '➖', '✖', '➗'];

    if (modes.every((m) => (stats[m]?['total'] ?? 0) == 0)) {
      return const Card(child: Padding(padding: EdgeInsets.all(20),
          child: Center(child: Text('まだ データが ありません', style: TextStyle(color: Colors.grey)))));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(modes.length, (i) {
            final mode    = modes[i];
            final total   = stats[mode]?['total']   ?? 0;
            final correct = stats[mode]?['correct'] ?? 0;
            final rate    = total == 0 ? 0.0 : correct / total;
            final pct     = (rate * 100).round();
            final barColor = pct >= 80 ? Colors.green : pct >= 50 ? Colors.orange : Colors.red;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text(labels[i], style: const TextStyle(fontSize: 18))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: rate, minHeight: 22,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 80,
                    child: Text(total == 0 ? '－' : '$pct% ($correct/$total)',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildWeakList() {
    if (history.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(16),
          child: Center(child: Text('まだ まちがいが ありません 🎉', style: TextStyle(color: Colors.grey)))));
    }

    final totalMiss = history.fold<int>(0, (sum, q) => sum + ((q['miss'] as int?) ?? 1));
    final hotCount  = history.where((q) => ((q['miss'] as int?) ?? 1) >= 3).length;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => HistoryPage(history: history)));
          _load(); // 確認済みで消した後に反映
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Text('${history.length} もん・のべ $totalMiss かい まちがい',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (hotCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text('🔴 $hotCount もん 3回以上',
                          style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                ]),
                const SizedBox(height: 4),
                const Text('タップして くわしく みる',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.blueGrey),
          ]),
        ),
      ),
    );
  }

  Widget _buildVisibilitySettings() {
    final items = [
      ('plus',   '➕ たしざん'),
      ('minus',  '➖ ひきざん'),
      ('multi',  '✖ かけざん'),
      ('div',    '➗ わりざん'),
      ('story',  '📖 ぶんしょう もんだい'),
      ('puzzle', '🧩 パズル'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: items.map((item) {
            final key = item.$1;
            final label = item.$2;
            final isVisible = !hiddenModes.contains(key);
            return SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(isVisible ? 'メニューに ひょうじ' : 'かくしている',
                  style: TextStyle(fontSize: 11,
                      color: isVisible ? Colors.green.shade600 : Colors.grey)),
              value: isVisible,
              activeColor: Colors.orange,
              onChanged: (v) {
                setState(() {
                  if (v) hiddenModes.remove(key);
                  else   hiddenModes.add(key);
                });
                _save();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: StatefulBuilder(builder: (context, setS) {
          final v = maxNum.round();
          String levelName; Color levelColor;
          if (v <= 10)      { levelName = '1けた';           levelColor = Colors.blue; }
          else if (v <= 20) { levelName = 'すこし2けた';     levelColor = Colors.green; }
          else if (v <= 50) { levelName = '2けた・ふつう';   levelColor = Colors.orange; }
          else              { levelName = '2けた・むずかしい'; levelColor = Colors.red; }

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🔢 むずかしさ', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Row(children: [
              Text('$v まで', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: levelColor)),
              const SizedBox(width: 8),
              Text('($levelName)', style: TextStyle(fontSize: 12, color: levelColor)),
            ]),
            Slider(value: maxNum, min: 10, max: 100, divisions: 9, activeColor: levelColor,
              onChanged: (val) { setS(() => maxNum = val); setState(() {}); },
              onChangeEnd: (_) => _save()),
            const Divider(),
            const Text('🏁 もんだい すう', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text('${goal.toInt()} もん',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            Slider(value: goal, min: 5, max: 50, divisions: 9,
              onChanged: (val) { setS(() => goal = val); setState(() {}); },
              onChangeEnd: (_) => _save()),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('🔘 えらぶモード', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(isSelect ? 'こたえを 4つから えらぶ' : 'すうじを じぶんで うつ',
                  style: const TextStyle(fontSize: 11)),
              value: isSelect,
              onChanged: (v) { setS(() => isSelect = v); setState(() {}); _save(); },
            ),
          ]);
        }),
      ),
    );
  }

  Widget _buildResetButton() {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
      icon: const Icon(Icons.delete_forever),
      label: const Text('きろくを すべて リセット'),
      onPressed: () async {
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('リセットしますか？'),
          content: const Text('せいかいりつ・にがてリストが すべて きえます。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: const Text('リセット', style: TextStyle(color: Colors.red))),
          ],
        ));
        if (ok == true) {
          await StatsManager.clearAll();
          await HistoryManager.clearAll();
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('wrongList');
          _load();
        }
      },
    );
  }
}

// ── ストーリーメニュー ────────────────────────────────────────────────
class StoryMenuScreen extends StatelessWidget {
  final int maxNum, goal; final bool isSelect;
  const StoryMenuScreen({super.key, required this.maxNum, required this.goal, required this.isSelect});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('どの おはなし？'), backgroundColor: Colors.orange.shade200, centerTitle: true),
    body: Container(color: Colors.orange.shade50, child: ListView(padding: const EdgeInsets.all(20), children: [
      _s(context, '➕ たしざん おはなし', MathMode.storyPlus,  Colors.blue.shade100),
      _s(context, '➖ ひきざん おはなし', MathMode.storyMinus, Colors.green.shade100),
      _s(context, '✖ かけざん おはなし',  MathMode.storyMulti, Colors.purple.shade100),
      _s(context, '➗ わりざん おはなし', MathMode.storyDiv,   Colors.teal.shade100),
    ])),
  );
  Widget _s(BuildContext ctx, String t, MathMode m, Color c) => Card(color: c,
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: ListTile(title: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: () => Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => MathGame(mode: m, maxNum: maxNum, goal: goal, isSelect: isSelect)))));
}

// ── パズルメニュー ───────────────────────────────────────────────────
class PuzzleMenuScreen extends StatelessWidget {
  final int maxNum, goal; final bool isSelect;
  const PuzzleMenuScreen({super.key, required this.maxNum, required this.goal, required this.isSelect});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('パズルに ちょうせん！'), backgroundColor: Colors.orange.shade200, centerTitle: true),
    body: Container(color: Colors.orange.shade50, child: ListView(padding: const EdgeInsets.all(20), children: [
      _p(context, '➕ たしざん パズル',       Colors.green.shade100,  1),
      _p(context, '➖ ひきざん パズル',       Colors.blue.shade100,   2),
      _p(context, '➕➕ 3つの たしざん',     Colors.purple.shade100, 3),
      _p(context, '🌀 ぜんぶ まざった パズル', Colors.red.shade100,   4),
    ])),
  );
  Widget _p(BuildContext ctx, String t, Color c, int lv) => Card(color: c,
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: ListTile(title: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: () => Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => MathGame(mode: MathMode.puzzle, maxNum: maxNum, goal: goal, isSelect: isSelect, pLv: lv)))));
}

// ── ゲーム画面 ───────────────────────────────────────────────────────
class MathGame extends StatefulWidget {
  final MathMode mode; final int maxNum, goal; final bool isSelect; final int pLv;
  const MathGame({super.key, required this.mode, required this.maxNum, required this.goal,
      required this.isSelect, this.pLv = 1});
  @override State<MathGame> createState() => _MathGameState();
}

class _MathGameState extends State<MathGame> {
  late MathMode curM;
  String pOp = '＋', emoji = '🍓', story = '';
  int n1 = 0, n2 = 0, target = 0, curQ = 1;
  List<int?> slots = []; List<int> choices = [];
  bool hint = false, showTable = false;
  int hintLevel = 0; // 0=非表示 1=1段階目 2=2段階目
  int correctCount = 0, wrongCount = 0;
  List<dynamic> wList = [];
  final TextEditingController _ansCtrl = TextEditingController();

  @override void dispose() { _ansCtrl.dispose(); super.dispose(); }

  @override void initState() {
    super.initState();
    curM = widget.mode;
    if (curM == MathMode.wrong) _loadWrongList(); else _generateQuestion();
  }

  Future<void> _loadWrongList() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> parsed = [];
    try { final d = prefs.getString('wrongList'); if (d != null) parsed = json.decode(d); } catch (_) {}
    if (!mounted) return;
    setState(() { wList = parsed; });
    if (wList.isEmpty) Navigator.pop(context); else _generateQuestion();
  }

  void _generateQuestion() {
    final r = Random(); showTable = false;
    if (widget.mode == MathMode.wrong) {
      if (wList.isEmpty) { _finishGame(); return; }
      final q = wList[0];
      curM = MathMode.fromString(q['m'] as String);
      n1 = q['n1'] as int; n2 = q['n2'] as int; target = q['t'] as int;
    } else {
      if (curQ > widget.goal) { _finishGame(); return; }
      if (curM == MathMode.puzzle) {
        _genPuzzle(r);
      } else if (curM.isPlus) {
        n1 = r.nextInt(widget.maxNum) + 1; n2 = r.nextInt(widget.maxNum) + 1; target = n1 + n2;
      } else if (curM.isMinus) {
        n1 = r.nextInt(widget.maxNum) + 5; n2 = r.nextInt(n1 - 1) + 1; target = n1 - n2;
      } else if (curM.isMulti) {
        n1 = r.nextInt(kMaxMultiNum) + 1; n2 = r.nextInt(kMaxMultiNum) + 1; target = n1 * n2;
      } else if (curM.isDiv) {
        target = r.nextInt(kMaxDivNum) + 1; n2 = r.nextInt(kMaxDivNum) + 1; n1 = target * n2;
      }
    }
    _setRandomStory(); _ansCtrl.clear(); hint = false; hintLevel = 0; _setupChoices(r); setState(() {});
  }

  void _genPuzzle(Random r) {
    if (widget.pLv == 4) {
      final type = r.nextInt(4);
      if (type == 0)      { pOp = '＋'; n1 = r.nextInt(20)+1; n2 = r.nextInt(20)+1; target = n1+n2; }
      else if (type == 1) { pOp = '－'; n1 = r.nextInt(20)+10; n2 = r.nextInt(n1-1)+1; target = n1-n2; }
      else if (type == 2) { pOp = '×'; n1 = r.nextInt(kMaxMultiNum)+1; n2 = r.nextInt(kMaxMultiNum)+1; target = n1*n2; }
      else                { pOp = '÷'; target = r.nextInt(kMaxDivNum)+1; n2 = r.nextInt(kMaxDivNum)+1; n1 = target*n2; }
      slots = List.filled(2, null);
    } else {
      pOp   = widget.pLv == 2 ? '－' : '＋';
      slots = List.filled(widget.pLv == 3 ? 3 : 2, null);
      target = widget.pLv == 3 ? r.nextInt(15)+5 : r.nextInt(15)+2;
    }
  }

  void _setupChoices(Random r) {
    choices = [target];
    while (choices.length < 4) { final d = target+r.nextInt(10)-5; if (d>=1 && !choices.contains(d)) choices.add(d); }
    choices.shuffle();
  }

  void _setRandomStory() {
    final r = Random();
    final names    = ['たろうくん','はなこちゃん','うさぎさん','おとうさん','おかあさん','くまさん','パンダくん'];
    final itemDict = {'アメ':'🍬','どんぐり':'🌰','シール':'⭐','いちご':'🍓','クッキー':'🍪','チョコ':'🍫'};
    final itemName = itemDict.keys.toList()[r.nextInt(itemDict.length)];
    emoji = itemDict[itemName]!;
    final name = names[r.nextInt(names.length)];
    if (curM == MathMode.storyPlus)  story = '$name は $itemName を $n1 こ もっていました。\nあとから $n2 こ もらうと、ぜんぶで なんこ？';
    else if (curM == MathMode.storyMinus) story = '$name は $itemName を $n1 こ もっていました。\n$n2 こ おともだちに あげると、のこりは なんこ？';
    else if (curM == MathMode.storyMulti) story = 'さらが $n1 まい あります。\n1まいの さらに $itemName を $n2 こずつ いれると、ぜんぶで なんこ？';
    else if (curM == MathMode.storyDiv)   story = '$n1 こ の $itemName を、$n2 人で おなじ数ずつ わけると、1人 なんこ？';
    else story = '';
  }

  Future<void> _checkAnswer(bool ok) async {
    await StatsManager.record(curM, ok);
    if (ok) correctCount++; else wrongCount++;
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> list = [];
    try { list = json.decode(prefs.getString('wrongList') ?? '[]'); } catch (_) {}
    if (ok) {
      if (widget.mode == MathMode.wrong) {
        if (list.isNotEmpty) list.removeAt(0);
        await prefs.setString('wrongList', json.encode(list));
        setState(() { if (wList.isNotEmpty) wList.removeAt(0); });
      }
    } else if (widget.mode != MathMode.wrong) {
      // にがてこくふく用リスト（重複なし）
      final exists = list.any((q) => q['m'] == curM.name && q['n1'] == n1 && q['n2'] == n2);
      if (!exists) { list.add({'m': curM.name, 'n1': n1, 'n2': n2, 't': target}); await prefs.setString('wrongList', json.encode(list)); }
      // 保護者用履歴（消えない・回数カウント）
      await HistoryManager.recordWrong(curM, n1, n2, target);
    }
    _showResultDialog(ok);
  }

  void _showResultDialog(bool ok) {
    showDialog(context: context, barrierDismissible: false, builder: (c) {
      if (ok) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && Navigator.canPop(c)) {
            Navigator.pop(c);
            if (widget.mode == MathMode.wrong) { if (wList.isEmpty) _finishGame(); else _generateQuestion(); }
            else { curQ++; _generateQuestion(); }
          }
        });
      }
      return AlertDialog(
        backgroundColor: ok ? Colors.orange : Colors.blueGrey,
        title: Text(ok ? '✨ せいかい！ ✨' : '❌ おしい！', textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        actions: ok ? null : [Center(child: TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('もういちど', style: TextStyle(color: Colors.white))))],
      );
    });
  }

  void _finishGame() {
    final total = correctCount + wrongCount;
    final pct   = total == 0 ? 0 : (correctCount * 100 / total).round();
    String comment; String medal;
    if (pct == 100)      { comment = 'かんぺき！ すごすぎる！';   medal = '🥇'; }
    else if (pct >= 80)  { comment = 'すばらしい！ よくできたね！'; medal = '🥈'; }
    else if (pct >= 50)  { comment = 'よくがんばったね！';         medal = '🥉'; }
    else                 { comment = 'つぎは もっと できるよ！';   medal = '⭐'; }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: const Center(child: Text('🎊 おわり！ 🎊',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(medal, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 8),
          Text(comment, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          // 結果カード
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _resultItem('✅ せいかい', correctCount, Colors.green),
                Container(width: 1, height: 44, color: Colors.orange.shade200),
                _resultItem('❌ ふせいかい', wrongCount, Colors.red),
              ]),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.orange.shade200, height: 1),
              ),
              _resultItem('📊 せいかいりつ', pct, Colors.blue, suffix: '%'),
            ]),
          ),
          const SizedBox(height: 20),
        ]),
        actions: [
          Center(child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () { Navigator.pop(c); Navigator.pop(context); },
            child: const Text('もどる', style: TextStyle(fontSize: 16)),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _resultItem(String label, int value, Color color, {String suffix = 'もん'}) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 4),
      Text('$value$suffix', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    String op = '＋';
    if (curM.isMinus) op = '－'; else if (curM.isMulti) op = '×'; else if (curM.isDiv) op = '÷';
    final titleText = widget.mode == MathMode.wrong
        ? '🔥 にがてを こくふく\n(のこり ${wList.length} もん)' : 'だい $curQ もん / ${widget.goal} もん';
    final progress = widget.mode == MathMode.wrong ? 0.0 : (curQ - 1) / widget.goal;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true, backgroundColor: Colors.orange.shade200,
        title: FittedBox(fit: BoxFit.scaleDown,
            child: Text(titleText, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.2))),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(value: progress, backgroundColor: Colors.orange.shade100,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange))),
      ),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(child: Column(children: [
          curM == MathMode.puzzle ? _buildPuzzleUI() : _buildNormalUI(op),
          if (curM.isMulti) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => setState(() => showTable = !showTable),
              icon: Icon(showTable ? Icons.visibility_off : Icons.visibility),
              label: const Text('かけざん はやみひょう'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade100)),
            if (showTable) _buildMultiTable(),
          ],
        ])))),
    );
  }

  Widget _buildNormalUI(String op) => Column(children: [
    const SizedBox(height: 30),
    story.isNotEmpty
        ? Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(elevation: 4, child: Padding(padding: const EdgeInsets.all(20),
                child: Text(story, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center))))
        : Text('$n1 $op $n2 ＝ ?', style: const TextStyle(fontSize: 55, fontWeight: FontWeight.bold)),
    const SizedBox(height: 30),
    widget.isSelect ? _buildChoiceGrid() : Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50),
        child: TextField(controller: _ansCtrl, keyboardType: TextInputType.number,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 38),
            onSubmitted: (v) => _checkAnswer(int.tryParse(v) == target))),
      const SizedBox(height: 12),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        onPressed: () => _checkAnswer(int.tryParse(_ansCtrl.text) == target),
        child: const Text('こたえあわせ！', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    ]),
    const SizedBox(height: 20),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (hintLevel == 0)
        TextButton.icon(
          onPressed: () => setState(() => hintLevel = 1),
          icon: const Icon(Icons.lightbulb_outline),
          label: const Text('ヒント①'),
        ),
      if (hintLevel == 1) ...[
        TextButton.icon(
          onPressed: () => setState(() => hintLevel = 0),
          icon: const Icon(Icons.lightbulb, color: Colors.amber),
          label: const Text('ヒントをかくす'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => setState(() => hintLevel = 2),
          icon: const Icon(Icons.lightbulb, color: Colors.orange),
          label: const Text('ヒント②'),
        ),
      ],
      if (hintLevel == 2)
        TextButton.icon(
          onPressed: () => setState(() => hintLevel = 0),
          icon: const Icon(Icons.lightbulb, color: Colors.orange),
          label: const Text('ヒントをかくす'),
        ),
    ]),
    if (hintLevel > 0) _buildHintArea(op, hintLevel),
  ]);

  Widget _buildChoiceGrid() => GridView.count(
    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15,
    padding: const EdgeInsets.symmetric(horizontal: 40), childAspectRatio: 1.8,
    children: choices.map((c) => ElevatedButton(
      style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      onPressed: () => _checkAnswer(c == target),
      child: Text('$c', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)))).toList());

  Widget _buildPuzzleUI() {
    // パズルルール説明文
    String ruleText;
    if (widget.pLv == 3) {
      ruleText = '3つの □ に すうじを いれて\nあわせると 赤い かずに なるように しよう！';
    } else if (pOp == '÷') {
      ruleText = '□ $pOp □ ＝ 赤いかず に なるように\n2つの □ に すうじを いれよう！\n（わりきれる かずを さがそう）';
    } else {
      ruleText = '□ $pOp □ ＝ 赤いかず に なるように\n2つの □ に すうじを いれよう！';
    }

    return Column(children: [
    const SizedBox(height: 16),
    // ルール説明カード
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        color: Colors.yellow.shade100,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📝 ', style: TextStyle(fontSize: 20)),
            Expanded(child: Text(ruleText,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.6))),
          ]),
        ),
      ),
    ),
    const SizedBox(height: 16),
    Text(target.toString(), style: const TextStyle(fontSize: 60, color: Colors.red, fontWeight: FontWeight.bold)),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _puzzleSlot(0), Text(pOp, style: const TextStyle(fontSize: 28)), _puzzleSlot(1),
      if (widget.pLv == 3) ...[const Text(' ＋ ', style: TextStyle(fontSize: 28)), _puzzleSlot(2)],
    ]),
    const SizedBox(height: 25),
    Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
      children: List.generate(21, (i) => ElevatedButton(
        onPressed: () {
          setState(() { final idx = slots.indexOf(null); if (idx != -1) slots[idx] = i; });
          if (!slots.contains(null)) {
            double res = 0;
            if (pOp == '＋')      res = (slots[0]! + slots[1]!).toDouble();
            else if (pOp == '－') res = (slots[0]! - slots[1]!).toDouble();
            else if (pOp == '×') res = (slots[0]! * slots[1]!).toDouble();
            else if (pOp == '÷') {
              if (slots[1] == 0) { setState(() => slots = List.filled(2, null)); return; }
              res = slots[0]! / slots[1]!;
            }
            if (widget.pLv == 3) res = (slots[0]! + slots[1]! + slots[2]!).toDouble();
            _checkAnswer(res == target.toDouble());
          }
        },
        child: Text('$i')))),
    TextButton(onPressed: () => setState(() => slots = List.filled(widget.pLv == 3 ? 3 : 2, null)),
        child: const Text('やりなおす')),
    ]);
  }

  Widget _puzzleSlot(int i) => Container(
    width: 50, height: 50, margin: const EdgeInsets.all(5),
    decoration: BoxDecoration(border: Border.all(color: Colors.orange), borderRadius: BorderRadius.circular(10)),
    child: Center(child: Text(slots[i]?.toString() ?? '?', style: const TextStyle(fontSize: 24))));

  Widget _buildMultiTable() => Card(
    elevation: 0, color: Colors.white, margin: const EdgeInsets.all(15),
    child: Padding(padding: const EdgeInsets.all(10),
      child: Table(border: TableBorder.all(color: Colors.grey.shade200, width: 0.5),
        children: List.generate(10, (r) => TableRow(children: List.generate(10, (c) {
          if (r == 0 && c == 0) return const Center(child: Text('×', style: TextStyle(fontSize: 14, color: Colors.grey)));
          if (r == 0 || c == 0) return Container(height: 35, color: Colors.orange.shade50,
            child: Center(child: Text('${r == 0 ? c : r}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))));
          final active = (r == n1 && c == n2);
          return Container(height: 35, color: active ? Colors.purple.shade200 : Colors.white,
            child: Center(child: Text('${r * c}', style: TextStyle(fontSize: 13, color: Colors.grey.shade800))));
        }))))));

  // 絵文字が多すぎる場合は上限で切り、残り数を表示
  Widget _emojiWrap(String em, int count, {double size = 24}) {
    const int cap = 20;
    if (count <= cap) {
      return Wrap(alignment: WrapAlignment.center,
          children: List.generate(count, (_) => Text(em, style: TextStyle(fontSize: size))));
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Wrap(children: List.generate(cap, (_) => Text(em, style: TextStyle(fontSize: size)))),
      Text(' … ×$count', style: TextStyle(fontSize: size * 0.7, color: Colors.grey)),
    ]);
  }

  Widget _buildHintArea(String op, int level) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: level == 1 ? Colors.amber.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: level == 1 ? Colors.amber.shade200 : Colors.orange.shade300),
      ),
      child: Column(children: [
        Text(level == 1 ? '💡 ヒント①' : '💡💡 ヒント②',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                color: level == 1 ? Colors.amber.shade800 : Colors.orange.shade800)),
        const SizedBox(height: 10),
        if (op == '＋') _hintPlus(level),
        if (op == '－') _hintMinus(level),
        if (op == '×') _hintMulti(level),
        if (op == '÷') _hintDiv(level),
      ]),
    );
  }

  // ── たしざん ──
  Widget _hintPlus(int level) {
    if (level == 1) {
      return Text('$n1 と $n2 を あわせると いくつ？\nひとつずつ かぞえて みよう！',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.6));
    }
    return Column(children: [
      _emojiWrap(emoji, n1, size: 26),
      const Padding(padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('➕', style: TextStyle(fontSize: 22))),
      _emojiWrap(emoji, n2, size: 26),
      const SizedBox(height: 6),
      Text('ぜんぶで $target こ！', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
    ]);
  }

  // ── ひきざん ──
  Widget _hintMinus(int level) {
    if (level == 1) {
      return Text('$n1 から $n2 を とると いくつ のこる？\n$n1 から ひとつずつ へらして みよう！',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.6));
    }
    return Column(children: [
      _emojiWrap(emoji, target, size: 26),
      const SizedBox(height: 4),
      Text('🍴 の $n2 こ を とると…', style: const TextStyle(fontSize: 14, color: Colors.grey)),
      const SizedBox(height: 4),
      _emojiWrap(emoji, target, size: 26),
      const SizedBox(height: 6),
      Text('$target こ のこる！', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
    ]);
  }

  // ── かけざん ──
  Widget _hintMulti(int level) {
    if (level == 1) {
      return Text('$n2 こずつの グループが $n1 つ あるよ！\nグループを たしていくと いくつ？',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.6));
    }
    return Column(children: [
      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8,
        children: List.generate(n1, (i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.purple.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.purple.shade50,
          ),
          child: Column(children: [
            Text('グループ ${i + 1}', style: TextStyle(fontSize: 10, color: Colors.purple.shade700)),
            Wrap(children: List.generate(n2, (_) => const Text('🍬', style: TextStyle(fontSize: 22)))),
          ]),
        ))),
      const SizedBox(height: 8),
      Text('$n2 × $n1 ＝ $target', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple)),
    ]);
  }

  // ── わりざん ──
  Widget _hintDiv(int level) {
    if (level == 1) {
      return Text('$n1 こを $n2 人で おなじ数ずつ わけると\n1人 なんこ もらえる？',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.6));
    }
    return Column(children: [
      Text('$n1 こを $n2 人に わけると…', style: const TextStyle(fontSize: 14, color: Colors.grey)),
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8,
        children: List.generate(n2, (i) => Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.teal.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.teal.shade50,
          ),
          child: Column(children: [
            Text('${i + 1}人め', style: TextStyle(fontSize: 10, color: Colors.teal.shade700)),
            Wrap(children: List.generate(target, (_) => Text(emoji, style: const TextStyle(fontSize: 20)))),
          ]),
        ))),
      const SizedBox(height: 8),
      Text('1人 $target こ！', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
    ]);
  }
}

// ── まちがい履歴ページ ────────────────────────────────────────────────
class HistoryPage extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  const HistoryPage({super.key, required this.history});

  @override State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    // miss降順でソートしてコピー
    _items = List.from(widget.history)
      ..sort((a, b) => ((b['miss'] as int?) ?? 1).compareTo((a['miss'] as int?) ?? 1));
  }

  String _opStr(MathMode m) {
    if (m.isPlus)  return '＋';
    if (m.isMinus) return '－';
    if (m.isMulti) return '×';
    return '÷';
  }

  Future<void> _dismiss(Map<String, dynamic> q) async {
    final mode = MathMode.fromString(q['m'] as String);
    await HistoryManager.dismiss(mode, q['n1'] as int, q['n2'] as int);
    setState(() => _items.remove(q));
  }

  @override
  Widget build(BuildContext context) {
    // モード別グループ
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final q in _items) {
      final m = q['m'] as String? ?? '';
      grouped.putIfAbsent(m, () => []).add(q);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('まちがい りれき'),
        backgroundColor: Colors.blueGrey.shade200,
        centerTitle: true,
      ),
      body: _items.isEmpty
          ? const Center(child: Text('すべて かくにん ずみです 🎉',
              style: TextStyle(fontSize: 16, color: Colors.grey)))
          : Container(
              color: Colors.blueGrey.shade50,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 凡例
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(spacing: 12, runSpacing: 6, children: [
                          _legend(Colors.red.shade100, Colors.red.shade300, '🔴 3回以上'),
                          _legend(Colors.orange.shade50, Colors.orange.shade200, '通常'),
                          const Text('✅ をタップすると かくにんずみにできます',
                              style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ]),
                      ),
                      // グループ別に表示
                      ...grouped.entries.map((e) {
                        final mode     = MathMode.fromString(e.key);
                        final problems = e.value;
                        final modeMiss = problems.fold<int>(0, (s, q) => s + ((q['miss'] as int?) ?? 1));
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // グループヘッダー
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                              child: Row(children: [
                                Text(mode.label,
                                    style: const TextStyle(
                                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                const SizedBox(width: 8),
                                Text('${problems.length}もん・$modeMiss回',
                                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400)),
                              ]),
                            ),
                            // 問題カード一覧
                            ...problems.map((q) {
                              final n1   = q['n1'] as int;
                              final n2   = q['n2'] as int;
                              final t    = q['t']  as int;
                              final miss = (q['miss'] as int?) ?? 1;
                              final qMode = MathMode.fromString(q['m'] as String);
                              final op   = _opStr(qMode);
                              final isHot = miss >= 3;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isHot ? Colors.red.shade50 : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isHot ? Colors.red.shade300 : Colors.orange.shade200,
                                    width: isHot ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(children: [
                                  // 式
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('$n1 $op $n2 ＝ ?',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: isHot ? Colors.red.shade700 : Colors.black87)),
                                      const SizedBox(height: 2),
                                      Text('こたえ: $t',
                                          style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                                    ]),
                                  ),
                                  // 間違い回数バッジ
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isHot ? Colors.red.shade400 : Colors.blueGrey.shade100,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text('$miss回',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isHot ? Colors.white : Colors.blueGrey.shade700)),
                                  ),
                                  if (isHot) const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Text('🔴', style: TextStyle(fontSize: 14)),
                                  ),
                                  const SizedBox(width: 8),
                                  // 確認済みボタン
                                  IconButton(
                                    icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                    tooltip: 'かくにんずみにする',
                                    onPressed: () => _dismiss(q),
                                  ),
                                ]),
                              );
                            }),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _legend(Color bg, Color border, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }
}
