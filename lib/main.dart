import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
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
  
  final List<Map<String, String>> _instructions = [
    {
      'title': 'Basic Calculations',
      'content': 'Simply type any mathematical expression and press Enter:\n5 + 10 * 2'
    },
    {
      'title': 'Variables',
      'content': 'Assign values to variables using the equals sign:\nx = 10\ny = 5\nx + y'
    },
    {
      'title': 'Comments',
      'content': 'Add comments using double slashes:\n5 * 10 // This is my calculation'
    },
    {
      'title': 'Functions',
      'content': 'Use mathematical functions:\nsin(30)\nsqrt(16)\nlog(100)'
    },
  ];

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

  // Show Settings Modal
  void _showSettingsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            color: _isDayTheme 
              ? Colors.white
              : Colors.grey[900],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle Bar
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: 16),
              // Title
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _isDayTheme ? Colors.black : Colors.white,
                ),
              ),
              SizedBox(height: 15),
              Divider(height: 1, thickness: 0.5, color: Colors.grey),
              
              // Dark Mode Toggle
              ListTile(
                leading: Icon(
                  _isDayTheme 
                    ? Icons.wb_sunny_outlined
                    : Icons.nightlight_outlined,
                  color: _isDayTheme ? Colors.black : Colors.white,
                ),
                title: Text(
                  'Dark Mode',
                  style: TextStyle(
                    color: _isDayTheme ? Colors.black : Colors.white,
                  ),
                ),
                trailing: Switch(
                  value: !_isDayTheme,
                  onChanged: (bool value) {
                    Navigator.pop(context);
                    _toggleTheme();
                  },
                  activeColor: Colors.blue,
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: Colors.grey),
              
              // Instructions
              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: _isDayTheme ? Colors.black : Colors.white,
                ),
                title: Text(
                  'Instructions',
                  style: TextStyle(
                    color: _isDayTheme ? Colors.black : Colors.white,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showInstructionsModal(context);
                },
              ),
              Divider(height: 1, thickness: 0.5, color: Colors.grey),
              
              // Feedback
              ListTile(
                leading: Icon(
                  Icons.chat_bubble_outline,
                  color: _isDayTheme ? Colors.black : Colors.white,
                ),
                title: Text(
                  'Feedback',
                  style: TextStyle(
                    color: _isDayTheme ? Colors.black : Colors.white,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showFeedbackComingSoonModal(context);
                },
              ),
              SizedBox(height: 16),
              
              // Done button
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: _isDayTheme ? Colors.white : Colors.grey[900],
                    side: BorderSide(
                      color: _isDayTheme ? Colors.black : Colors.white,
                      width: 1.0,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4.0)),
                    padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  ),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16.0,
                      color: _isDayTheme ? Colors.black : Colors.white,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Helper widget for settings items
  Widget _buildSettingsItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
    bool topRadius = false,
    bool bottomRadius = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(topRadius ? 16 : 0),
            topRight: Radius.circular(topRadius ? 16 : 0),
            bottomLeft: Radius.circular(bottomRadius ? 16 : 0),
            bottomRight: Radius.circular(bottomRadius ? 16 : 0),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Icon with background
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 18,
                        color: iconColor,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  // Title
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _isDayTheme ? Colors.black87 : Colors.white,
                    ),
                  ),
                  Spacer(),
                  // Trailing widget
                  trailing,
                ],
              ),
            ),
            // Only add divider if not the last item
            if (!bottomRadius)
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: _isDayTheme 
                    ? CupertinoColors.systemGrey5
                    : CupertinoColors.systemGrey4.withOpacity(0.3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Show Instructions Modal
  void _showInstructionsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            color: _isDayTheme 
              ? Colors.white
              : Colors.grey[900],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle Bar
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: 20),
              // Title
              Text(
                'Instructions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _isDayTheme ? Colors.black : Colors.white,
                ),
              ),
              SizedBox(height: 15),
              Divider(height: 1, thickness: 0.5, color: Colors.grey),
              // Scrollable content
              Expanded(
                child: Container(
                  margin: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Scrollbar(
                    radius: Radius.circular(3),
                    thumbVisibility: true,
                    child: ListView(
                      padding: EdgeInsets.all(10),
                      children: [
                        _buildInstructionSection(
                          'Keyboard Shortcuts',
                          [
                            TextSpan(text: 'Tap results column on right to close keyboard'),
                          ],
                        ),
                        Divider(height: 24, thickness: 0.5, color: Colors.grey.withOpacity(0.5)),
                        // Basic Calculations section
                        _buildInstructionSection(
                          'Basic Calculations',
                          [
                            TextSpan(text: 'Simply type any mathematical expression and press Enter:\n'),
                            TextSpan(text: '5 + 10 * 2'),
                          ],
                        ),
                        
                        Divider(height: 24, thickness: 0.5, color: Colors.grey.withOpacity(0.5)),
                        
                        // Variables section
                        _buildInstructionSection(
                          'Variables',
                          [
                            TextSpan(text: 'Assign values to variables using the equals sign:\n'),
                            TextSpan(
                              text: 'x',
                              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: ' = 10\n'),
                            TextSpan(
                              text: 'y',
                              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: ' = 5\n'),
                            TextSpan(
                              text: 'x',
                              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: ' + '),
                            TextSpan(
                              text: 'y',
                              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        
                        Divider(height: 24, thickness: 0.5, color: Colors.grey.withOpacity(0.5)),
                        
                        // Comments section
                        _buildInstructionSection(
                          'Comments',
                          [
                            TextSpan(text: 'Add comments using double slashes:\n'),
                            TextSpan(text: '5 * 10 '),
                            TextSpan(
                              text: '// This is my calculation',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        
                        Divider(height: 24, thickness: 0.5, color: Colors.grey.withOpacity(0.5)),
                        
                        // Functions section
                        _buildInstructionSection(
                          'Functions',
                          [
                            TextSpan(text: 'Use mathematical functions:\n'),
                            TextSpan(text: 'sin(30)\nsqrt(16)\nlog(100)'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Done button
              Padding(
                padding: const EdgeInsets.only(bottom: 24, top: 8),
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: _isDayTheme ? Colors.white : Colors.grey[900],
                    side: BorderSide(
                      color: _isDayTheme ? Colors.black : Colors.white,
                      width: 1.0,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4.0)),
                    padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  ),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16.0,
                      color: _isDayTheme ? Colors.black : Colors.white,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Helper method to build instruction sections
  Widget _buildInstructionSection(String title, List<TextSpan> content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _isDayTheme ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isDayTheme 
              ? Colors.grey[100]
              : Colors.grey[850],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isDayTheme 
                ? Colors.grey[300]!
                : Colors.grey[700]!,
              width: 1,
            ),
          ),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 15,
                height: 1.5,
                color: _isDayTheme 
                  ? Colors.black
                  : Colors.white,
              ),
              children: content,
            ),
          ),
        ),
      ],
    );
  }

  // Show Feedback Coming Soon Modal
  void _showFeedbackComingSoonModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            color: _isDayTheme 
              ? Colors.white
              : Colors.grey[900],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle Bar
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: 20),
              // Decorative orbit circles
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer orbit
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isDayTheme 
                          ? Colors.grey[300]!
                          : Colors.grey[700]!,
                        width: 1,
                      ),
                    ),
                  ),
                  // Middle orbit
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isDayTheme 
                          ? Colors.grey[300]!
                          : Colors.grey[700]!,
                        width: 1,
                      ),
                    ),
                  ),
                  // Rocket with glowing effect
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.orange.withOpacity(0.2),
                          Colors.transparent
                        ],
                        radius: 0.7,
                      ),
                    ),
                    child: Center(
                      child: Transform.rotate(
                        angle: 0.8, // Angle in radians (about 45 degrees)
                        child: Icon(
                          Icons.rocket_launch,
                          size: 40,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ),
                  // Small planet 1
                  Positioned(
                    top: 10,
                    right: 20,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  // Small planet 2
                  Positioned(
                    bottom: 20,
                    left: 15,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 30),
              // Title with gradient
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [Colors.orange, Colors.red],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds);
                },
                child: Text(
                  'Coming Soon!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 16),
              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  'We\'re working on making NOTIVA even better.\nFeedback feature will be available soon!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _isDayTheme ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.7),
                  ),
                ),
              ),
              SizedBox(height: 30),
              // Done button
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: _isDayTheme ? Colors.white : Colors.grey[900],
                    side: BorderSide(
                      color: _isDayTheme ? Colors.black : Colors.white,
                      width: 1.0,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4.0)),
                    padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  ),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16.0,
                      color: _isDayTheme ? Colors.black : Colors.white,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  // Replace theme toggle with settings icon
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: _isDayTheme ? Colors.black : Colors.white,
                      ),
                      onPressed: () {
                        _showSettingsModal(context);
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