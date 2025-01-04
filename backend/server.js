require("dotenv").config();
const express = require("express");
const bodyParser = require("body-parser");
const http = require("http");
const WebSocket = require("ws");
const fs = require("fs");
const Redis = require("ioredis");

const app = express();
const HTTP_PORT = process.env.PORT || 8080;

// Redis setup
const redisPublisher = new Redis(process.env.REDISCLOUD_URL); // Redis publisher
const redisSubscriber = new Redis(process.env.REDISCLOUD_URL); // Redis subscriber

redisPublisher.on("error", (err) => {
  console.error("Redis Publisher Error:", err);
});
redisSubscriber.on("error", (err) => {
  console.error("Redis Subscriber Error:", err);
});

// File paths
const VALID_CARDS_FILE = "valid-cards.json";
const SCAN_HISTORY_FILE = "scan-history.json";

// Middleware
app.use(bodyParser.json());

// Initialize JSON files
if (!fs.existsSync(VALID_CARDS_FILE)) {
  fs.writeFileSync(VALID_CARDS_FILE, JSON.stringify({ cards: [] }, null, 2));
}
if (!fs.existsSync(SCAN_HISTORY_FILE)) {
  fs.writeFileSync(SCAN_HISTORY_FILE, JSON.stringify([], null, 2));
}

// Function to publish file change announcements
const publishFileChange = (message) => {
  redisPublisher.publish("file-change", JSON.stringify(message));
};

// Endpoint: Handle RFID scans
app.post("/scan", (req, res) => {
  const { enteredKey } = req.body;
  const validCards = JSON.parse(fs.readFileSync(VALID_CARDS_FILE)).cards;
  const isValid = validCards.includes(enteredKey);

  const newEntry = {
    enteredKey,
    success: isValid,
    time: new Date().toISOString(),
  };

  const scanHistory = JSON.parse(fs.readFileSync(SCAN_HISTORY_FILE));
  scanHistory.push(newEntry);
  fs.writeFileSync(SCAN_HISTORY_FILE, JSON.stringify(scanHistory, null, 2));

  // Publish to Redis
  publishFileChange({
    file: "scan-history.json",
    newEntry,
  });

  res.json({ success: isValid });
});

// Endpoint: Add new valid card
app.post("/add-card", (req, res) => {
  const { newCard } = req.body;
  const validCards = JSON.parse(fs.readFileSync(VALID_CARDS_FILE)).cards;

  if (!validCards.includes(newCard)) {
    validCards.push(newCard);
    fs.writeFileSync(
      VALID_CARDS_FILE,
      JSON.stringify({ cards: validCards }, null, 2)
    );

    // Publish to Redis
    publishFileChange({
      file: "valid-cards.json",
      action: "add-card",
      card: newCard,
    });

    res.json({ message: "Card added successfully!" });
  } else {
    res.json({ message: "Card already exists!" });
  }
});

// WebSocket server setup
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// WebSocket connection handling
wss.on("connection", (ws, req) => {
  console.log("WebSocket client connected!");

  // Subscribe to Redis channel
  redisSubscriber.subscribe("file-change", (err) => {
    if (err) {
      console.error("Failed to subscribe to file-change channel:", err);
      ws.close(1011, "Subscription error");
    } else {
      console.log("Client subscribed to file-change channel.");
    }
  });

  // Handle Redis messages
  redisSubscriber.on("message", (channel, message) => {
    if (channel === "file-change" && ws.readyState === WebSocket.OPEN) {
      ws.send(message); // Send file change message to the WebSocket client
    }
  });

  // Pinging mechanism to keep the connection alive
  const pingInterval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.ping(); // Send ping to the client
    }
  }, 25000); // Ping every 25 seconds (Heroku's timeout is 55 seconds)

  // Handle WebSocket disconnection
  ws.on("close", () => {
    console.log("WebSocket client disconnected.");
    clearInterval(pingInterval); // Clear the ping interval

    redisSubscriber.unsubscribe("file-change", (err) => {
      if (err) {
        console.error("Failed to unsubscribe from file-change channel:", err);
      } else {
        console.log("Client unsubscribed from file-change channel.");
      }
    });
  });

  // Handle errors and unexpected disconnections
  ws.on("error", (error) => {
    console.error("WebSocket error:", error);
    ws.terminate();
  });
});

// Start the server
server.listen(HTTP_PORT, () => {
  console.log(`Server running on port ${HTTP_PORT}`);
});
