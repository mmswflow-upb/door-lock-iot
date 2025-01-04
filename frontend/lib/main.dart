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
  const MyApp({super.key});

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
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String serverUrl = dotenv.env['SERVER_URL'] ?? '';
  final String wsUrl = dotenv.env['WS_URL'] ?? '';

  WebSocketChannel? channel;
  List<Map<String, dynamic>> updates = [];
  List<String> validCards = [];
  TextEditingController cardController = TextEditingController();
  FocusNode cardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    connectToWebSocket();
  }

  @override
  void dispose() {
    cardFocusNode.dispose();
    cardController.dispose();
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

  Future<void> addCard(String newKeyCode) async {
    try {
      final response = await http.post(
        Uri.parse("$serverUrl/add-card"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"newKeyCode": newKeyCode}),
      );

      // Use the response body as the message
      String responseMessage = response.body.isNotEmpty
          ? response.body
          : "Unexpected response from the server.";

      // Display the response message in a Snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(responseMessage)),
      );
    } catch (error) {
      print("Error adding card: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to add card. Please try again.")),
      );
    }
  }



  Future<void> fetchValidCards() async {
    try {
      final response = await http.get(Uri.parse("$serverUrl/valid-cards"));
      if (response.statusCode == 200) {
        final List<dynamic> cardData = jsonDecode(response.body);
        setState(() {
          validCards = cardData.map((card) => card['card'] as String).toList();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to fetch valid cards: ${response.statusCode}")),
        );
      }
    } catch (error) {
      print("Error fetching valid cards: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching valid cards.")),
      );
    }
  }
  Future<void> deleteCard(String card) async {
    try {
      final response = await http.delete(
        Uri.parse("$serverUrl/delete-card"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"card": card}),
      );

      String responseMessage = response.body.isNotEmpty
          ? response.body
          : "Unexpected response from the server.";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(responseMessage)),
      );

      // Refresh updates if necessary
      fetchValidCards();
    } catch (error) {
      print("Error deleting card: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete card. Please try again.")),
      );
    }
  }

  void showValidCardsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder(
          future: fetchValidCards(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: Text("Valid Cards"),
                content: Center(child: CircularProgressIndicator()),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text("Close"),
                  ),
                ],
              );
            } else if (snapshot.hasError) {
              return AlertDialog(
                title: Text("Error"),
                content: Text("Failed to fetch valid cards. Please try again."),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text("Close"),
                  ),
                ],
              );
            } else {
              return AlertDialog(
                title: Text("Valid Cards"),
                content: validCards.isEmpty
                    ? Text("No valid cards found.")
                    : SingleChildScrollView(
                  child: ListBody(
                    children: validCards.map((card) {
                      return ListTile(
                        title: Text(card),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            deleteCard(card);
                            Navigator.of(context).pop(); // Close the modal
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text("Close"),
                  ),
                ],
              );
            }
          },
        );
      },
    );
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
                    focusNode: cardFocusNode,
                    controller: cardController,
                    decoration: InputDecoration(labelText: "Key Code"),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  child: Text("Add Key Code"),
                  onPressed: () {
                    if (cardController.text.isNotEmpty) {
                      addCard(cardController.text);
                      cardController.clear();
                      cardFocusNode.requestFocus();
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => showValidCardsModal(context),
              child: Text("Show Valid Cards"),
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
