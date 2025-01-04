import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env"); // Load the .env file
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RFID Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String serverUrl = dotenv.env['SERVER_URL'] ?? '';
  final String wsUrl = dotenv.env['WS_URL'] ?? '';

  WebSocketChannel? channel;
  List<Map<String, dynamic>> updates = [];
  TextEditingController cardController = TextEditingController();

  @override
  void initState() {
    super.initState();
    connectToWebSocket();
  }

  @override
  void dispose() {
    channel?.sink.close();
    super.dispose();
  }

  void connectToWebSocket() {
    channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    channel?.stream.listen(
          (message) {
        setState(() {
          updates.add(jsonDecode(message));
        });
      },
      onError: (error) {
        print("WebSocket Error: $error");
      },
      onDone: () {
        print("WebSocket connection closed.");
      },
    );
  }

  Future<void> addCard(String cardId) async {
    try {
      final response = await http.post(
        Uri.parse("$serverUrl/add-card"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"newCard": cardId}),
      );

      final result = jsonDecode(response.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'])),
      );
    } catch (error) {
      print("Error adding card: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to add card.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("RFID Manager")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cardController,
                    decoration: InputDecoration(labelText: "Card ID"),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  child: Text("Add Card"),
                  onPressed: () {
                    if (cardController.text.isNotEmpty) {
                      addCard(cardController.text);
                      cardController.clear();
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 20),
            Expanded(
              child: updates.isEmpty
                  ? Center(child: Text("No updates yet."))
                  : ListView.builder(
                itemCount: updates.length,
                itemBuilder: (context, index) {
                  final update = updates[index];
                  return ListTile(
                    title: Text(update['file']),
                    subtitle: Text(
                      update.containsKey('newEntry')
                          ? "UID: ${update['newEntry']['enteredKey']} - Success: ${update['newEntry']['success']}"
                          : "Action: ${update['action']} - Card: ${update['card']}",
                    ),
                    trailing: Text(update['time'] ?? ""),
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
