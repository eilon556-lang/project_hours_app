import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.init();
  runApp(ProjectHoursApp());
}

/* ===========================
   Models
   =========================== */

class Project {
  final int? id;
  final String projectId; // number as string
  final String projectName;

  Project({this.id, required this.projectId, required this.projectName});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projectId': projectId,
      'projectName': projectName,
    };
  }

  factory Project.fromMap(Map<String, dynamic> m) {
    return Project(
      id: m['id'] as int?,
      projectId: m['projectId'] as String,
      projectName: m['projectName'] as String,
    );
  }
}

class Entry {
  final int? id;
  final String date; // yyyy-MM-dd
  final String projectId;
  final String projectName;
  final double hours;

  Entry({
    this.id,
    required this.date,
    required this.projectId,
    required this.projectName,
    required this.hours,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'projectId': projectId,
      'projectName': projectName,
      'hours': hours,
    };
  }

  factory Entry.fromMap(Map<String, dynamic> m) {
    return Entry(
      id: m['id'] as int?,
      date: m['date'] as String,
      projectId: m['projectId'] as String,
      projectName: m['projectName'] as String,
      hours: (m['hours'] is int) ? (m['hours'] as int).toDouble() : (m['hours'] as num).toDouble(),
    );
  }
}

/* ===========================
   Database Helper (SQLite)
   =========================== */

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    String databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'project_hours.db');

    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            projectId TEXT NOT NULL,
            projectName TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            projectId TEXT NOT NULL,
            projectName TEXT NOT NULL,
            hours REAL NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE app_settings(
            key TEXT PRIMARY KEY,
            value TEXT
          );
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_settings(
              key TEXT PRIMARY KEY,
              value TEXT
            );
          ''');
        }
      },
    );
  }

  Future<int> insertProject(Project p) async {
    return await _db!.insert('projects', p.toMap());
  }

  Future<int> deleteProject(int id) async {
    return await _db!.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteEntriesByProject(String projectId) async {
    return await _db!.delete('entries', where: 'projectId = ?', whereArgs: [projectId]);
  }

  Future<List<Project>> getProjects() async {
    final rows = await _db!.query('projects', orderBy: 'projectName COLLATE NOCASE');
    return rows.map((r) => Project.fromMap(r)).toList();
  }

  Future<int> insertEntry(Entry e) async {
    return await _db!.insert('entries', e.toMap());
  }

  Future<List<Entry>> getEntries({int limit = 500}) async {
    final rows = await _db!.query('entries', orderBy: 'date DESC', limit: limit);
    return rows.map((r) => Entry.fromMap(r)).toList();
  }

  Future<List<Entry>> getEntriesForMonth(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final s = DateFormat('yyyy-MM-dd').format(start);
    final e = DateFormat('yyyy-MM-dd').format(end);
    final rows = await _db!.rawQuery(
      'SELECT * FROM entries WHERE date >= ? AND date < ? ORDER BY projectName COLLATE NOCASE',
      [s, e],
    );
    return rows.map((r) => Entry.fromMap(r)).toList();
  }

  Future<void> deleteMonth(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final s = DateFormat('yyyy-MM-dd').format(start);
    final e = DateFormat('yyyy-MM-dd').format(end);
    await _db!.delete('entries', where: 'date >= ? AND date < ?', whereArgs: [s, e]);
  }

  // settings
  Future<void> setSetting(String key, String value) async {
    await _db!.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db!.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }
}

/* ===========================
   App
   =========================== */

class ProjectHoursApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project Hours',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/* ===========================
   Home Page
   =========================== */

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Project> projects = [];
  List<Entry> entries = [];

  Project? selectedProject;
  final _hoursController = TextEditingController();
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  Future<void> _reloadAll() async {
    projects = await DatabaseHelper.instance.getProjects();
    entries = await DatabaseHelper.instance.getEntries();
    setState(() {});
  }

  Future<void> _pickDate(BuildContext ctx) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        selectedDate = d;
      });
    }
  }

  Future<void> _saveEntry() async {
    if (selectedProject == null) {
      _showMessage('בחר פרויקט לפני שמירה');
      return;
    }
    final hrsText = _hoursController.text.trim();
    if (hrsText.isEmpty) {
      _showMessage('הכנס שעות');
      return;
    }
    final hrs = double.tryParse(hrsText.replaceAll(',', '.'));
    if (hrs == null) {
      _showMessage('הזן מספר שעות תקין');
      return;
    }
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final e = Entry(
      date: dateStr,
      projectId: selectedProject!.projectId,
      projectName: selectedProject!.projectName,
      hours: hrs,
    );
    await DatabaseHelper.instance.insertEntry(e);
    _hoursController.clear();
    await _reloadAll();
    _showMessage('נשמר בהצלחה');
  }

  void _showMessage(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _openProjects() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectsPage()));
    await _reloadAll();
  }

  void _openReport() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportPage()));
  }

  void _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('שעות פרויקטים'),
        actions: [
          IconButton(icon: Icon(Icons.settings), onPressed: _openSettings),
          IconButton(icon: Icon(Icons.list_alt), onPressed: _openReport),
          IconButton(icon: Icon(Icons.manage_accounts), onPressed: _openProjects),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Project dropdown + manage button
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Project>(
                    value: selectedProject,
                    hint: Text('בחר פרויקט'),
                    items: projects.map((p) {
                      return DropdownMenuItem<Project>(
                        value: p,
                        child: Text('${p.projectName}  (${p.projectId})'),
                      );
                    }).toList(),
                    onChanged: (p) {
                      setState(() {
                        selectedProject = p;
                      });
                    },
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _openProjects,
                  icon: Icon(Icons.add_box),
                  label: Text('פרויקטים'),
                ),
              ],
            ),

            SizedBox(height: 12),
            // Date and hours
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(context),
                    child: AbsorbPointer(
                      child: TextFormField(
                        decoration: InputDecoration(labelText: 'תאריך'),
                        controller: TextEditingController(
                          text: DateFormat('yyyy-MM-dd').format(selectedDate),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _hoursController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'שעות'),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(onPressed: _saveEntry, child: Text('שמור')),
              ],
            ),

            SizedBox(height: 16),
            // Recent entries
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text('אין כניסות עדיין'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return ListTile(
                          title: Text('${e.projectName} — ${e.hours}h'),
                          subtitle: Text('${e.date} (ID: ${e.projectId})'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===========================
   Projects Page
   =========================== */

class ProjectsPage extends StatefulWidget {
  @override
  _ProjectsPageState createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  List<Project> projects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    projects = await DatabaseHelper.instance.getProjects();
    setState(() {});
  }

  Future<void> _addProject() async {
    final pid = _idCtrl.text.trim();
    final pname = _nameCtrl.text.trim();
    if (pid.isEmpty || pname.isEmpty) {
      _show('יש למלא מספר ושם פרויקט');
      return;
    }
    final p = Project(projectId: pid, projectName: pname);
    await DatabaseHelper.instance.insertProject(p);
    _idCtrl.clear();
    _nameCtrl.clear();
    await _load();
  }

  Future<void> _deleteProject(Project p) async {
    if (p.id == null) return;
    final alsoEntries = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('מחיקת פרויקט'),
        content: Text('למחוק גם את כל ההזנות של הפרויקט "${p.projectName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('רק פרויקט')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('פרויקט + הזנות')),
        ],
      ),
    );
    if (alsoEntries == true) {
      await DatabaseHelper.instance.deleteEntriesByProject(p.projectId);
    }
    await DatabaseHelper.instance.deleteProject(p.id!);
    await _load();
  }

  void _show(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ניהול פרויקטים'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Flexible(
                  flex: 3,
                  child: TextField(
                    controller: _idCtrl,
                    decoration: InputDecoration(labelText: 'מספר פרויקט'),
                    keyboardType: TextInputType.text,
                  ),
                ),
                SizedBox(width: 8),
                Flexible(
                  flex: 6,
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(labelText: 'שם פרויקט'),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(onPressed: _addProject, child: Text('הוסף')),
              ],
            ),
            SizedBox(height: 12),
            Expanded(
              child: projects.isEmpty
                  ? Center(child: Text('אין פרויקטים עדיין'))
                  : ListView.builder(
                      itemCount: projects.length,
                      itemBuilder: (ctx, i) {
                        final p = projects[i];
                        return ListTile(
                          title: Text(p.projectName),
                          subtitle: Text('מספר: ${p.projectId}'),
                          trailing: IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () => _deleteProject(p),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===========================
   Settings Page (employee info)
   =========================== */

class SettingsPage extends StatefulWidget {
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nameCtrl = TextEditingController();
  final _numCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _nameCtrl.text = await DatabaseHelper.instance.getSetting('employee_name') ?? '';
    _numCtrl.text = await DatabaseHelper.instance.getSetting('employee_number') ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    await DatabaseHelper.instance.setSetting('employee_name', _nameCtrl.text.trim());
    await DatabaseHelper.instance.setSetting('employee_number', _numCtrl.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('נשמר')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('הגדרות עובד')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(decoration: InputDecoration(labelText: 'שם עובד'), controller: _nameCtrl),
            SizedBox(height: 8),
            TextField(decoration: InputDecoration(labelText: 'מספר עובד'), controller: _numCtrl),
            SizedBox(height: 12),
            ElevatedButton(onPressed: _save, child: Text('שמור')),
          ],
        ),
      ),
    );
  }
}

/* ===========================
   Report Page
   =========================== */

class ReportPage extends StatefulWidget {
  @override
  _ReportPageState createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<String, double> agg = {}; // key: projectId||projectName -> hours
  double totalHours = 0.0;

  String employeeName = '';
  String employeeNumber = '';

  @override
  void initState() {
    super.initState();
    _loadForMonth(selectedMonth);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    employeeName = await DatabaseHelper.instance.getSetting('employee_name') ?? '';
    employeeNumber = await DatabaseHelper.instance.getSetting('employee_number') ?? '';
    setState(() {});
  }

  Future<void> _loadForMonth(DateTime month) async {
    final year = month.year;
    final mon = month.month;
    final entries = await DatabaseHelper.instance.getEntriesForMonth(year, mon);
    final map = <String, double>{};
    double tot = 0.0;
    for (var e in entries) {
      final key = '${e.projectId}||${e.projectName}';
      map[key] = (map[key] ?? 0) + e.hours;
      tot += e.hours;
    }
    setState(() {
      agg = map;
      totalHours = tot;
    });
  }

  Future<void> _pickMonth() async {
    final d = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      selectedMonth = DateTime(d.year, d.month, 1);
      await _loadForMonth(selectedMonth);
    }
  }

  pw.Widget _cell(String text, {bool bold = false, bool center = false, pw.pw.PdfColor? bg}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      color: bg,
      alignment: center ? pw.Alignment.center : pw.Alignment.centerRight,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 10),
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();

    // אם הוספת פונט עברית ב-assets, ניתן לטעון כאן:
    // final fontData = await rootBundle.load('assets/fonts/Assistant-Regular.ttf');
    // final hebFont = pw.Font.ttf(fontData);
    // final theme = pw.ThemeData.withFont(base: hebFont);
    final theme = pw.ThemeData.base();

    final monthTitle = DateFormat('yyyy-MM').format(selectedMonth);
    final printDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

    final rows = agg.entries.map((e) {
      final parts = e.key.split('||');
      final pid = parts[0];
      final pname = parts[1];
      final hrs = e.value;
      final pct = totalHours > 0 ? (hrs / totalHours) * 100 : 0.0;
      return {
        'pct': pct,
        'pid': pid,
        'pname': pname,
        'hrs': hrs,
      };
    }).toList()
      ..sort((a, b) => (b['pct'] as double).compareTo(a['pct'] as double));

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          textDirection: pw.TextDirection.rtl,
        ),
        build: (pw.Context ctx) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('תאריך הדפסה: $printDate', style: const pw.TextStyle(fontSize: 10)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('שם עובד: ${employeeName.isEmpty ? "-" : employeeName}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('מספר עובד: ${employeeNumber.isEmpty ? "-" : employeeNumber}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text('דו״ח חודשי — $monthTitle',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(width: 0.8),
              columnWidths: {
                0: const pw.FixedColumnWidth(70),
                1: const pw.FixedColumnWidth(110),
                2: const pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  children: [
                    _cell('אחוזים', bold: true, center: true),
                    _cell('מס פרויקט', bold: true, center: true),
                    _cell('שם פרויקט', bold: true, center: true),
                  ],
                ),
                ...rows.map((r) {
                  final pct = (r['pct'] as double);
                  final pid = r['pid'] as String;
                  final pname = r['pname'] as String;
                  return pw.TableRow(
                    children: [
                      _cell('${pct.toStringAsFixed(2)}%', center: true,
                        bg: pct > 0 ? pw.pw.pw.PdfColors.green400 : pw.pw.pw.PdfColors.white),
                      _cell(pid, center: true),
                      _cell(pname),
                    ],
                  );
                }),
                pw.TableRow(
                  children: [
                    _cell('100%', bold: true, center: true),
                    _cell('סה״כ', bold: true, center: true),
                    _cell('', bold: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 150, height: 1, color: pw.pw.pw.PdfColors.black),
                  pw.SizedBox(height: 6),
                  pw.Text('חתימה', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Report_$monthTitle.pdf');

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('מחיקת נתונים'),
        content: Text('למחוק את כל הנתונים של $monthTitle?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('לא')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('כן')),
        ],
      ),
    );

    if (shouldDelete == true) {
      await DatabaseHelper.instance.deleteMonth(selectedMonth.year, selectedMonth.month);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נתוני החודש נמחקו')),
      );
      await _loadForMonth(selectedMonth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'he').format(selectedMonth);
    return Scaffold(
      appBar: AppBar(
        title: Text('דו״ח חודשי'),
        actions: [
          IconButton(icon: Icon(Icons.picture_as_pdf), onPressed: agg.isEmpty ? null : _exportPdf),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Text('חודש: ', style: TextStyle(fontSize: 16)),
                SizedBox(width: 8),
                ElevatedButton(onPressed: _pickMonth, child: Text(monthLabel)),
                SizedBox(width: 12),
                ElevatedButton(onPressed: () => _loadForMonth(selectedMonth), child: Text('טען')),
              ],
            ),
            SizedBox(height: 12),
            Expanded(
              child: agg.isEmpty
                  ? Center(child: Text('אין כניסות בחודש זה'))
                  : ListView(
                      children: agg.entries.map((e) {
                        final parts = e.key.split('||');
                        final pid = parts[0];
                        final pname = parts[1];
                        final hrs = e.value;
                        final pct = totalHours > 0 ? hrs / totalHours * 100 : 0.0;
                        return ListTile(
                          title: Text('$pname'),
                          subtitle: Text('מספר: $pid'),
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${hrs.toStringAsFixed(2)} h'),
                              Text('${pct.toStringAsFixed(2)} %'),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Text('סה״כ שעות: ${totalHours.toStringAsFixed(2)}', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}