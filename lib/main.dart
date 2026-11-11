import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() => runApp(const UnexellApp());

class UnexellApp extends StatefulWidget {
  const UnexellApp({super.key});

  @override
  State<UnexellApp> createState() => _UnexellAppState();
}

class _UnexellAppState extends State<UnexellApp> {
  bool dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UNEXELL',
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff159879)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff159879),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(
        dark: dark,
        toggleTheme: () => setState(() => dark = !dark),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool dark;
  final VoidCallback toggleTheme;

  const HomePage({
    super.key,
    required this.dark,
    required this.toggleTheme,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> sheetNames = ['Sheet1'];
  final List<List<String>> cells = List.generate(
    40,
    (_) => List.generate(12, (_) => ''),
  );

  final Map<String, Color> cellColors = {};
  final Set<String> boldCells = {};

  final TextEditingController formulaController = TextEditingController();

  int activeSheet = 0;
  int selectedRow = 0;
  int selectedCol = 0;

  bool bold = false;

  String get cellId => '$selectedRow-$selectedCol';

  String columnName(int n) {
    String result = '';
    n++;
    while (n > 0) {
      int r = (n - 1) % 26;
      result = String.fromCharCode(65 + r) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
  }

  String get cellAddress =>
      '${columnName(selectedCol)}${selectedRow + 1}';

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('unexell_data');

    if (saved != null) {
      try {
        final data = jsonDecode(saved);
        setState(() {
          sheetNames
            ..clear()
            ..addAll(List<String>.from(data['names']));
          if (sheetNames.isEmpty) sheetNames.add('Sheet1');

          final savedCells = data['cells'] as List;
          for (int r = 0; r < savedCells.length && r < cells.length; r++) {
            for (int c = 0;
                c < savedCells[r].length && c < cells[r].length;
                c++) {
              cells[r][c] = savedCells[r][c].toString();
            }
          }
        });
      } catch (_) {}
    }

    updateFormula();
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'unexell_data',
      jsonEncode({
        'names': sheetNames,
        'cells': cells,
      }),
    );
  }

  void updateFormula() {
    formulaController.text = cells[selectedRow][selectedCol];
  }

  void selectCell(int r, int c) {
    setState(() {
      selectedRow = r;
      selectedCol = c;
      bold = boldCells.contains('$r-$c');
      updateFormula();
    });
  }

  void updateCell(String value) {
    setState(() {
      cells[selectedRow][selectedCol] = value;
    });
    saveData();
  }

  double numberAt(int r, int c) {
    if (r < 0 || c < 0 || r >= cells.length || c >= cells[r].length) {
      return 0;
    }

    String value = cells[r][c];

    if (value.startsWith('=')) {
      return double.tryParse(value.substring(1)) ?? 0;
    }

    return double.tryParse(value) ?? 0;
  }

  String displayValue(int r, int c) {
    String value = cells[r][c];

    if (!value.startsWith('=')) return value;

    String formula = value.substring(1).trim().toUpperCase();

    final range = RegExp(
      r'^(SUM|AVERAGE|MIN|MAX)\(([A-Z]+[0-9]+):([A-Z]+[0-9]+)\)$',
    ).firstMatch(formula);

    if (range != null) {
      int col(String letters) {
        int n = 0;
        for (final x in letters.codeUnits) {
          n = n * 26 + x - 64;
        }
        return n - 1;
      }

      final a = RegExp(r'^([A-Z]+)([0-9]+)$')
          .firstMatch(range.group(2)!)!;
      final b = RegExp(r'^([A-Z]+)([0-9]+)$')
          .firstMatch(range.group(3)!)!;

      int c1 = col(a.group(1)!);
      int c2 = col(b.group(1)!);
      int r1 = int.parse(a.group(2)!) - 1;
      int r2 = int.parse(b.group(2)!) - 1;

      List<double> values = [];

      for (int rr = r1; rr <= r2; rr++) {
        for (int cc = c1; cc <= c2; cc++) {
          values.add(numberAt(rr, cc));
        }
      }

      if (values.isEmpty) return '0';

      double result = 0;

      switch (range.group(1)) {
        case 'SUM':
          result = values.reduce((a, b) => a + b);
          break;
        case 'AVERAGE':
          result = values.reduce((a, b) => a + b) / values.length;
          break;
        case 'MIN':
          result = values.reduce((a, b) => a < b ? a : b);
          break;
        case 'MAX':
          result = values.reduce((a, b) => a > b ? a : b);
          break;
      }

      return result.toString();
    }

    return 'Formula';
  }

  Future<void> editCell() async {
    final controller = TextEditingController(
      text: cells[selectedRow][selectedCol],
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $cellAddress'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter value or formula',
            helperText: 'Example: =SUM(A1:A5)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      updateCell(result);
      updateFormula();
    }
  }

  void addSheet() {
    setState(() {
      sheetNames.add('Sheet${sheetNames.length + 1}');
      activeSheet = sheetNames.length - 1;
    });
    saveData();
  }

  Future<void> renameSheet() async {
    final controller = TextEditingController(
      text: sheetNames[activeSheet],
    );

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename worksheet'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      setState(() => sheetNames[activeSheet] = name);
      saveData();
    }
  }

  void addRow() {
    setState(() {
      cells.add(List.generate(cells.first.length, (_) => ''));
    });
    saveData();
  }

  void addColumn() {
    setState(() {
      for (final row in cells) {
        row.add('');
      }
    });
    saveData();
  }

  void toggleBold() {
    setState(() {
      if (bold) {
        boldCells.remove(cellId);
      } else {
        boldCells.add(cellId);
      }
      bold = !bold;
    });
  }

  void changeCellColor(Color color) {
    setState(() => cellColors[cellId] = color);
  }

  void sortColumn() {
    setState(() {
      final data = cells.skip(1).toList();
      data.sort((a, b) =>
          a[selectedCol].compareTo(b[selectedCol]));
      for (int i = 1; i < cells.length; i++) {
        cells[i] = data[i - 1];
      }
    });
    saveData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.grid_on, color: Color(0xff159879)),
            SizedBox(width: 9),
            Text(
              'UNEXELL',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New sheet',
            onPressed: addSheet,
            icon: const Icon(Icons.note_add_outlined),
          ),
          IconButton(
            tooltip: 'Change theme',
            onPressed: widget.toggleTheme,
            icon: Icon(
              widget.dark ? Icons.light_mode : Icons.dark_mode,
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),

      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: theme.colorScheme.surfaceContainer,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    cellAddress,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.functions),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: formulaController,
                    decoration: const InputDecoration(
                      hintText: 'Value or formula',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: updateCell,
                  ),
                ),
                IconButton(
                  tooltip: 'Save cell',
                  onPressed: () => updateCell(formulaController.text),
                  icon: const Icon(Icons.check_circle_outline),
                ),
              ],
            ),
          ),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Bold',
                  onPressed: toggleBold,
                  icon: Icon(
                    Icons.format_bold,
                    color: bold ? const Color(0xff159879) : null,
                  ),
                ),
                PopupMenuButton<Color>(
                  tooltip: 'Cell color',
                  icon: const Icon(Icons.format_color_fill),
                  onSelected: changeCellColor,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: Colors.yellow,
                      child: Text('Yellow'),
                    ),
                    PopupMenuItem(
                      value: Colors.lightGreen,
                      child: Text('Green'),
                    ),
                    PopupMenuItem(
                      value: Colors.lightBlue,
                      child: Text('Blue'),
                    ),
                    PopupMenuItem(
                      value: Colors.pink,
                      child: Text('Pink'),
                    ),
                    PopupMenuItem(
                      value: Colors.white,
                      child: Text('White'),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Add row',
                  onPressed: addRow,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                IconButton(
                  tooltip: 'Add column',
                  onPressed: addColumn,
                  icon: const Icon(Icons.view_column_outlined),
                ),
                IconButton(
                  tooltip: 'Sort column',
                  onPressed: sortColumn,
                  icon: const Icon(Icons.sort),
                ),
                const SizedBox(width: 8),
                Text(
                  'Offline spreadsheet',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 43,
                  dataRowMaxHeight: 48,
                  horizontalMargin: 8,
                  columnSpacing: 8,
                  columns: [
                    const DataColumn(label: Text('#')),
                    ...List.generate(
                      cells.first.length,
                      (c) => DataColumn(
                        label: Text(
                          columnName(c),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: List.generate(
                    cells.length,
                    (r) => DataRow(
                      cells: [
                        DataCell(
                          Text(
                            '${r + 1}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        ...List.generate(
                          cells[r].length,
                          (c) {
                            final id = '$r-$c';
                            final selected =
                                r == selectedRow && c == selectedCol;

                            return DataCell(
                              InkWell(
                                onTap: () => selectCell(r, c),
                                onDoubleTap: () {
                                  selectCell(r, c);
                                  editCell();
                                },
                                child: Container(
                                  width: 105,
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    color: cellColors[id] ??
                                        (selected
                                            ? theme.colorScheme.primaryContainer
                                            : null),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xff159879)
                                          : theme.dividerColor,
                                      width: selected ? 2 : .5,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    displayValue(r, c),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: boldCells.contains(id)
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          Container(
            height: 55,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: theme.colorScheme.surfaceContainer,
            child: Row(
              children: [
                IconButton(
                  onPressed: addSheet,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: sheetNames.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(sheetNames[index]),
                        selected: activeSheet == index,
                        onSelected: (_) => setState(() {
                          activeSheet = index;
                        }),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Rename sheet',
                  onPressed: renameSheet,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xff159879),
        foregroundColor: Colors.white,
        onPressed: editCell,
        icon: const Icon(Icons.edit),
        label: const Text('Edit cell'),
      ),
    );
  }
}
