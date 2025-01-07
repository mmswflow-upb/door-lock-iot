import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env"); // Load the .env file
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RFID Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
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
    fetchScanHistory(); // Initial load of scan history
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
          (_) {
        fetchScanHistory(); // Fetch updated scan history on notification
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

      String responseMessage = response.body.isNotEmpty
          ? response.body
          : "Unexpected response from the server.";

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

  Future<void> fetchScanHistory() async {
    try {
      final response = await http.get(Uri.parse("$serverUrl/scan-history"));
      if (response.statusCode == 200) {
        final List<dynamic> historyData = jsonDecode(response.body);
        setState(() {
          updates = historyData.cast<Map<String, dynamic>>();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to fetch scan history: ${response.statusCode}")),
        );
      }
    } catch (error) {
      print("Error fetching scan history: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching scan history.")),
      );
    }
  }

  Future<void> fetchValidCards() async {
    try {
      final response = await http.get(Uri.parse("$serverUrl/valid-cards"));
      if (response.statusCode == 200) {
        final List<dynamic> cardData = jsonDecode(response.body);
        setState(() {
          validCards = List<String>.from(cardData); // Directly assign the flat list
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
                title: const Text("Valid Cards"),
                content: const Center(child: CircularProgressIndicator()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close"),
                  ),
                ],
              );
            } else if (snapshot.hasError) {
              return AlertDialog(
                title: const Text("Error"),
                content: const Text("Failed to fetch valid cards. Please try again."),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close"),
                  ),
                ],
              );
            } else {
              return AlertDialog(
                title: const Text("Valid Cards"),
                content: validCards.isEmpty
                    ? const Text("No valid cards found.")
                    : SingleChildScrollView(
                  child: ListBody(
                    children: validCards.map((card) {
                      return ListTile(
                        title: Text(card),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close"),
                  ),
                ],
              );
            }
          },
        );
      },
    );
  }

  void showScanHistoryModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void updateHistory() async {
              try {
                final response = await http.get(Uri.parse("$serverUrl/scan-history"));
                if (response.statusCode == 200) {
                  final List<dynamic> historyData = jsonDecode(response.body);
                  setState(() {
                    updates = historyData.cast<Map<String, dynamic>>();
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to fetch scan history: ${response.statusCode}")),
                  );
                }
              } catch (error) {
                print("Error fetching scan history: $error");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error fetching scan history.")),
                );
              }
            }

            // Fetch history initially
            updateHistory();

            return AlertDialog(
              title: const Text("Scan History"),
              content: updates.isEmpty
                  ? const Center(child: Text("No scan history found."))
                  : SingleChildScrollView(
                child: ListBody(
                  children: updates.map((update) {
                    return ListTile(
                      title: Text("Key: ${update['enteredKey']}"),
                      subtitle: Text(
                          "Success: ${update['success']} | Time: ${update['time']}"),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("RFID Manager")),
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
                    decoration: const InputDecoration(labelText: "Key Code"),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  child: const Text("Add Key Code"),
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
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => showValidCardsModal(context),
              child: const Text("Show Valid Cards"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => showScanHistoryModal(context),
              child: const Text("Show Scan History"),
            ),
          ],
        ),
      ),
    );
  }
}
