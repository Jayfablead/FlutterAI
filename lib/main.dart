import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Flutter AI",
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        elevation: 0,
        centerTitle: true,
      ),
      body: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final GenerativeModel _model;
  late final ChatSession _chat;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = false;

  stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  String _voiceInput = '';

  @override
  void initState() {
    _model = GenerativeModel(model: "gemini-pro", apiKey: dotenv.env['API_KEY']!);
    _chat = _model.startChat();
    super.initState();
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speechToText.initialize(
        onStatus: (val) => setState(() {
          if (val == "done") {
            _isListening = false;
            _textController.text = _voiceInput;
            _sendChatMessage(_voiceInput);
          }
        }),
        onError: (val) => setState(() => _isListening = false),
      );
      if (available) {
        setState(() => _isListening = true);
        _speechToText.listen(onResult: (val) => setState(() {
          _voiceInput = val.recognizedWords;
        }));
      }
    } else {
      setState(() => _isListening = false);
      _speechToText.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasApiKey = dotenv.env['API_KEY'] != null && dotenv.env['API_KEY']!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: hasApiKey
                ? _chat.history.isEmpty
                ? Center(child: Text('Start Asking Anything'))
                : ListView.builder(
              controller: _scrollController,
              itemBuilder: (context, idx) {
                final content = _chat.history.toList()[idx];
                final text = content.parts
                    .whereType<TextPart>()
                    .map<String>((e) => e.text)
                    .join('');
                return MessageWidget(
                  text: text,
                  isFromUser: content.role == 'user',
                );
              },
              itemCount: _chat.history.length,
            )
                : ListView(
              children: const [
                Text('No API key found. Please provide an API Key.'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 25,
              horizontal: 15,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _listen,
                ),
                Expanded(
                  child: TextFormField(
                    controller: _textController,
                    autofocus: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(15),
                      hintText: 'Enter a prompt...',
                      border: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(14),
                        ),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(14),
                        ),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                    onFieldSubmitted: (String value) {
                      _sendChatMessage(value);
                    },
                  ),
                ),
                const SizedBox.square(
                  dimension: 15,
                ),
                InkWell(
                  onTap: () async {
                    _sendChatMessage(_textController.text);
                  },
                  child: Container(
                    height: 50,
                    width: 50,
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(80),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: !_loading
                        ? Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.secondaryContainer,
                    )
                        : CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                    ),
                  ),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendChatMessage(String message) async {
    if (message.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please Type Something.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await _chat.sendMessage(Content.text(message));
      final text = response.text;
      if (text == null) {
        debugPrint('No response from API.');
        return;
      }
      setState(() => _loading = false);
      _scrollToEnd();
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      _textController.clear();
      setState(() => _loading = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }
}

class MessageWidget extends StatelessWidget {
  final String text;
  final bool isFromUser;

  const MessageWidget({
    super.key,
    required this.text,
    required this.isFromUser,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            decoration: BoxDecoration(
              color: isFromUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 15,
              horizontal: 20,
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: MarkdownBody(
              selectable: true,
              data: text,
            ),
          ),
        ),
      ],
    );
  }
}
