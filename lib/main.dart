import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Assistant',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF111111),
      ),
      home: const VoiceAssistant(),
    );
  }
}

class VoiceAssistant extends StatefulWidget {
  const VoiceAssistant({Key? key}) : super(key: key);

  @override
  _VoiceAssistantState createState() => _VoiceAssistantState();
}

class _VoiceAssistantState extends State<VoiceAssistant> {
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _text = '';
  final String _serverUrl = 'http://192.168.162.182:5001/command';
  final MethodChannel platform = MethodChannel('overlay_channel');

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _initializeSpeech();
    _setupMethodChannel();
  }

  void _initializeTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
  }

  void _initializeSpeech() async {
    await _speech.initialize(
      onStatus: (status) => print('Speech status: $status'),
      onError: (errorNotification) => print('Speech error: $errorNotification'),
    );
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'startListening':
          _startListening();
          break;
        case 'stopListening':
          _stopListening();
          break;
        case 'updateOverlayContent':
          // Handle overlay updates if needed
          break;
        case 'multiple_contacts':
          await _handleMultipleContacts(call.arguments);
          break;
      }
    });
  }

  void _startListening() {
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          setState(() => _text = result.recognizedWords);
          _processCommand(_text);
        } else {
          setState(() => _text = result.recognizedWords);
        }
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    // Process the command when listening stops
    if (_text.isNotEmpty) {
      _processCommand(_text);
    }
  }

  Future<void> _processCommand(String command) async {
    try {
      final response = await http.post(
        Uri.parse(_serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command': command}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        switch (data['action']) {
          case 'send_message':
            String phoneNumber = data['phone_number'];
            if (phoneNumber != null && phoneNumber.isNotEmpty) {
              await _sendMessage(
                  data['recipient'], data['message'], phoneNumber);
              await _speak('Sending your message to ${data['recipient']}.');
            } else {
              await _speak(
                  'Could not find a phone number for ${data['recipient']}.');
            }
            break;
          case 'multiple_contacts':
            await _handleMultipleContacts(data);
            break;
          case 'open_app':
            await _launchApp(data['package'], data['app_name']);
            break;
          case 'open_url':
            await _launchUrl(data['url'], data['query']);
            break;
          case 'change_setting':
            await _changeSystemSetting(
                data['category'], data['setting'], data['command']);
            break;
          case 'play_music':
            String songName = data['song_name'];
            String service = data['service'];
            await _playMusic(songName, service);
            break;
          case 'unknown_command':
            String geminiResponse = data['response'];
            await _speak(geminiResponse);
            break;
          default:
            await _speak("I couldn't process that command.");
        }
      } else {
        print('Failed to communicate with server: ${response.statusCode}');
        await _speak('There was an error communicating with the server.');
      }
    } catch (e) {
      print('Error sending command to server: $e');
      await _speak('There was an error processing your command.');
    }
  }

  Future<void> _playMusic(String songName, String service) async {
    if (service.toLowerCase() == "spotify") {
      final Uri uri = Uri.parse('spotify:search:$songName');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        await _speak('Playing $songName on Spotify.');
      } else {
        await _speak('Could not open Spotify.');
      }
    } else if (service.toLowerCase() == "youtube") {
      final Uri uri =
          Uri.parse('https://www.youtube.com/results?search_query=$songName');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        await _speak('Playing $songName on YouTube.');
      } else {
        await _speak('Could not open YouTube.');
      }
    } else {
      await _speak("I can only play music on Spotify or YouTube.");
    }
  }

  Future<void> _handleMultipleContacts(Map<String, dynamic> data) async {
    List<String> contactNumbers = List<String>.from(data['phone_numbers']);
    // Use TTS to read out names or numbers and ask user to specify
    await _speak(
        "I found multiple contacts for ${data['recipient']}. Please specify which one:");

    for (var number in contactNumbers) {
      await _speak(number); // Read out each number
    }

    // Start listening again after reading out the numbers
    // You may want to implement a more robust way to determine which number is selected
    // For simplicity, let's assume we listen for a single word response that matches the number format.

    // Start listening for user selection
    _startListeningForSelection(contactNumbers);
  }

  void _startListeningForSelection(List<String> contactNumbers) {
    // Listen for user input to select a number
    _speech.listen(
      onResult: (result) async {
        if (result.finalResult) {
          String selectedNumber = result.recognizedWords;

          if (contactNumbers.contains(selectedNumber)) {
            // Send message using the selected number
            await http.post(
              Uri.parse(_serverUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'command': "send message to $selectedNumber that I'll be late"
              }),
            );
            await _speak("Message sent to $selectedNumber.");
          } else {
            await _speak("I didn't recognize that number. Please try again.");
          }

          // Stop listening after processing selection
          _stopListening();
        }
      },
    );
  }

  Future<void> _sendMessage(
      String recipient, String message, String phoneNumber) async {
    final Uri uri =
        Uri.parse('whatsapp://send?text=$message&phone=$phoneNumber');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await _speak('Could not send message via WhatsApp.');
    }
  }

  Future<void> _launchApp(String packageName, String appName) async {
    final Uri appUri = Uri.parse('android-app://$packageName');

    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri);
      await _speak('Opening $appName');
    } else {
      print('Could not launch $appName');
      await _speak('Could not launch $appName.');
    }
  }

  Future<void> _launchUrl(String url, String query) async {
    final Uri uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      await _speak('Searching for $query');
    } else {
      await _speak('Could not perform the search.');
    }
  }

  Future<void> _changeSystemSetting(
      String category, String setting, String command) async {
    switch (category) {
      case 'audio':
        await _speak('Changing volume settings.');
        break;
      case 'display':
        if (setting == 'brightness') {
          await _speak('Adjusting screen brightness.');
        } else if (setting == 'dark mode') {
          await _speak('Toggling dark mode.');
        }
        break;
      case 'network':
        await _speak('Modifying Wi-Fi settings.');
        break;
      case 'bluetooth':
        await _speak('Adjusting Bluetooth settings.');
        break;
      default:
        await _speak('Sorry, I cannot change that setting.');
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Container(),
    );
  }
}
