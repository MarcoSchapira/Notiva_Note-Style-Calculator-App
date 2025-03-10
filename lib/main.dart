import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(NotesApp());

class NotesApp extends StatefulWidget {
  @override
  _NotesAppState createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Full Page Notes App',
      debugShowCheckedModeBanner: false,
      // The home widget itself handles loading/saving theme and notes
      home: NotePage(),
    );
  }
}

class NotePage extends StatefulWidget {
  NotePage();

  @override
  _NotePageState createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  TextEditingController _noteController = TextEditingController();
  ScrollController _leftScrollController = ScrollController();
  ScrollController _rightScrollController = ScrollController();

  CodeController _codeController = CodeController();
  double _dividerPosition = 0.66;
  final double _initialDividerPosition = 0.66;

  List<String> results = [];
  Map<String, double> myVar = {};

  bool _isDayTheme = true;
  String _oldCodeText = '';

  @override
void initState() {
  super.initState();
  _loadThemePreference().then((_) {
    _loadNotes().then((_) {
      // After notes are loaded, update results once to populate myVar
      _updateResults(); 
      
      // Now that myVar is populated, initialize the code controller with the updated vars
      _initializeCodeControllerWithCurrentVars();

      // Set up the listener after everything is initialized
      _codeController.addListener(() {
        if (_codeController.text.endsWith('\n') && _codeController.text != _oldCodeText) {
          _updateResults();
        }
        _oldCodeText = _codeController.text;
      });
    });
  });

  // Synchronize scrolling between left and right columns
  _leftScrollController.addListener(() {
    if (_leftScrollController.offset != _rightScrollController.offset) {
      _rightScrollController.jumpTo(_leftScrollController.offset);
    }
  });
  _rightScrollController.addListener(() {
    if (_rightScrollController.offset != _leftScrollController.offset) {
      _leftScrollController.jumpTo(_rightScrollController.offset);
    }
  });
}

  // Load theme preference from SharedPreferences
  Future<void> _loadThemePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool savedTheme = prefs.getBool('isDayTheme') ?? true;
    setState(() {
      _isDayTheme = savedTheme;
    });
  }

  // Save theme preference to SharedPreferences
  Future<void> _saveThemePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDayTheme', _isDayTheme);
  }

  void _toggleTheme() {
    setState(() {
      _isDayTheme = !_isDayTheme;
    });
    _saveThemePreference();
  }

  // Load notes from SharedPreferences
  Future<void> _loadNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String savedNotes = prefs.getString('notes') ?? '';
    setState(() {
      _noteController.text = savedNotes;
      _codeController.text = savedNotes;
      _oldCodeText = savedNotes;
    });
  }

  // Save notes to SharedPreferences
  Future<void> _saveNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('notes', _codeController.text);
  }

  void _initializeCodeControllerWithCurrentVars({String? text}) {

    Map<String, TextStyle> myVarStyles = {
      for (var key in myVar.keys)
        key: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
    };

    TextSelection oldSelection = _codeController.selection;
    double oldOffset = _leftScrollController.hasClients ? _leftScrollController.offset : 0.0;

    // Keep the current text (loaded notes) or use provided text
    String currentText = text ?? _codeController.text;

    _codeController = CodeController(
      text: currentText,
      patternMap: {
        r"\B//.*\b":
            TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
      },
      stringMap: {
        ...myVarStyles,
      },
    );

    // Add listener after re-initializing
    _codeController.addListener(() {
      if (_codeController.text.endsWith('\n') && _codeController.text != _oldCodeText) {
        _updateResults();
      }
      _oldCodeText = _codeController.text;
      // Save notes whenever text changes
      _saveNotes();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeController.selection = oldSelection;
      if (_leftScrollController.hasClients) {
        _leftScrollController.jumpTo(oldOffset);
      }
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _updateResults() {
    List<String> lines = _codeController.text.split('\n');
    List<String> updatedResults = [];
    Map<String, double> updatedVars = {};
    Parser parser = Parser();
    String newComment = '';
    List<String> updatedComments = [];

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      if (line.contains('//')) {
        newComment = line.substring(line.indexOf('//'), line.length).trim();
        updatedComments.add(newComment);

        line = line.substring(0, line.indexOf('//'));
      }
      line = line.trim();

      if (line.isEmpty) {
        updatedResults.add('');
        continue;
      }

      try {
        ContextModel contextModel = ContextModel();
        updatedVars.forEach((name, value) {
          contextModel.bindVariable(Variable(name), Number(value));
        });

        if (line.contains('=')) {
          int index = line.indexOf('=');
          String varName = line.substring(0, index).trim();
          String expression = line.substring(index + 1).trim();
          Expression exp = parser.parse(expression);
          double eval = exp.evaluate(EvaluationType.REAL, contextModel);

          updatedVars[varName] = eval;
          updatedResults.add(_formatResult(eval));
        } else {
          Expression exp = parser.parse(line);
          double eval = exp.evaluate(EvaluationType.REAL, contextModel);
          updatedResults.add(_formatResult(eval));
        }
      } catch (e) {
        updatedResults.add('');
      }
    }

    setState(() {
      results = updatedResults;
      myVar = updatedVars;
      _noteController.text = _codeController.text;
      _initializeCodeControllerWithCurrentVars(text: _codeController.text);
    });
  }

  String _formatResult(double value) {
    if (value.isInfinite || value.isNaN) {
      return value.toString();
    } else if (value == value.toInt()) {
      return value.toInt().toString();
    } else {
      return value.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: MaterialApp(
          theme: _isDayTheme ? ThemeData.light() : ThemeData.dark(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            appBar: AppBar(
              toolbarHeight: 70.0,
              elevation: 0.0,
              backgroundColor: _isDayTheme ? Colors.white : Colors.grey[900],
              automaticallyImplyLeading: false,
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _noteController.clear();
                          results.clear();
                          myVar.clear();
                          _codeController.clear();
                          _dividerPosition = _initialDividerPosition;
                        });
                        _saveNotes(); // Save after clearing
                      },
                      style: TextButton.styleFrom(
                        backgroundColor:
                            _isDayTheme ? Colors.white : Colors.grey[900],
                        side: BorderSide(
                          color: _isDayTheme ? Colors.black : Colors.white,
                          width: 1.0,
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.0)),
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 18.0,
                          color: _isDayTheme ? Colors.black : Colors.white,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  Spacer(),
                  Text(
                    'NOTIVA',
                    style: TextStyle(
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                      color: _isDayTheme ? Colors.black : Colors.white,
                    ),
                  ),
                  Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: IconButton(
                      icon: Icon(
                        _isDayTheme
                            ? Icons.wb_sunny_outlined
                            : Icons.nightlight_outlined,
                        color: _isDayTheme ? Colors.black : Colors.white,
                      ),
                      onPressed: () {
                        _toggleTheme();
                      },
                    ),
                  ),
                ],
              ),
              iconTheme:
                  IconThemeData(color: _isDayTheme ? Colors.black : Colors.white),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: constraints.maxWidth * _dividerPosition,
                      child: _buildLeftSide(),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (DragUpdateDetails details) {
                        setState(() {
                          double newPosition =
                              (_dividerPosition * constraints.maxWidth +
                                      details.delta.dx) /
                                  constraints.maxWidth;
                          _dividerPosition = newPosition.clamp(0.2, 0.8);
                        });
                      },
                      child: Container(
                        width: 5.0,
                        color: _isDayTheme ? Colors.grey : Colors.grey,
                      ),
                    ),
                    Expanded(child: _buildRightSide()),
                  ],
                );
              },
            ),
          ),
        ),
      );

  Widget _buildLeftSide() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _leftScrollController,
            child: Container(
              padding:
                  const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
              alignment: Alignment.topLeft,
              child: CodeField(
                controller: _codeController,
                textStyle: TextStyle(
                  fontSize: 18.0,
                  height: 1.5,
                  color: _isDayTheme ? Colors.black : Colors.white,
                ),
                cursorColor: _isDayTheme ? Colors.black : Colors.white,
                wrap: false,
                minLines: 20,
                maxLines: null,
                lineNumberStyle: LineNumberStyle(
                  width: 10,
                  textStyle: TextStyle(color: Colors.transparent),
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightSide() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _rightScrollController,
            child: Container(
              padding: const EdgeInsets.only(
                  left: 16.0, right: 16.0, bottom: 16.0, top: 10),
              alignment: Alignment.topLeft,
              child: Text(
                results.join('\n'),
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: 18.0,
                  height: 1.5,
                  color: _isDayTheme ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
