require("dotenv").config();
const express = require("express");
const bodyParser = require("body-parser");
const http = require("http");
const WebSocket = require("ws");
const mongoose = require("mongoose");
const Redis = require("ioredis");

// Import Mongoose models
const ValidCard = require("./models/ValidCard");
const ScanHistory = require("./models/ScanHistory");

const app = express();
const HTTP_PORT = process.env.PORT || 8080;

// Redis setup
const redisPublisher = new Redis(process.env.REDISCLOUD_URL);
const redisSubscriber = new Redis(process.env.REDISCLOUD_URL);

redisPublisher.on("error", (err) => {
  console.error("Redis Publisher Error:", err);
});
redisSubscriber.on("error", (err) => {
  console.error("Redis Subscriber Error:", err);
});

// Middleware
app.use(bodyParser.json());

// Connect to MongoDB
mongoose
  .connect(process.env.MONGO_URI)
  .then(() => console.log("Connected to MongoDB"))
  .catch((err) => console.error("MongoDB connection error:", err));

// Function to publish file changes
const publishFileChange = (message) => {
  redisPublisher.publish("file-change", JSON.stringify(message));
};

// Endpoint: Scan a card
app.post("/scan", async (req, res) => {
  console.log("Scan request received!");

  try {
    const { enteredKey } = req.body;

    // Check if the card is valid
    const cardExists = await ValidCard.findOne({ card: enteredKey });
    const isValid = !!cardExists;

    // Log the scan in the database
    const newEntry = await ScanHistory.create({
      enteredKey,
      success: isValid,
    });

    // Publish to Redis
    publishFileChange({
      event: "new-scan",
      newEntry,
    });

    // Respond to the client
    if (isValid) {
      res.status(200).send("Access granted!");
    } else {
      res.status(401).send("Access denied!");
    }
  } catch (error) {
    console.error("Error handling scan request:", error);
    res.status(500).send("Internal server error.");
  }
});

// Endpoint: Add a new valid card
app.post("/add-card", async (req, res) => {
  console.log("Add card request received!");

  const { card } = req.body;
  if (!card) {
    return res.status(400).send("Card is required.");
  }

  try {
    const newCard = await ValidCard.create({ card });

    // Publish to Redis
    publishFileChange({
      event: "add-card",
      card: newCard,
    });

    res.status(200).send("Card added successfully!");
  } catch (error) {
    if (error.code === 11000) {
      res.status(400).send("Card already exists.");
    } else {
      console.error("Error adding card:", error);
      res.status(500).send("Internal server error.");
    }
  }
});

// Endpoint: Get scan history
app.get("/scan-history", async (req, res) => {
  try {
    const history = await ScanHistory.find().sort({ time: -1 }).limit(50);
    res.status(200).json(history);
  } catch (error) {
    console.error("Error retrieving scan history:", error);
    res.status(500).send("Internal server error.");
  }
});

// WebSocket server setup
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

wss.on("connection", (ws) => {
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
      ws.send(message);
    }
  });

  // Pinging mechanism
  const pingInterval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.ping();
    }
  }, 25000);

  ws.on("close", () => {
    console.log("WebSocket client disconnected.");
    clearInterval(pingInterval);
    redisSubscriber.unsubscribe("file-change");
  });

  ws.on("error", (error) => {
    console.error("WebSocket error:", error);
    ws.terminate();
  });
});

// Start the server
server.listen(HTTP_PORT, () => {
  console.log(`Server running on port ${HTTP_PORT}`);
  console.log("MONGO_URI:", process.env.MONGO_URI);
});
