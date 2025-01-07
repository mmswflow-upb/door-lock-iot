require("dotenv").config();
const express = require("express");
const bodyParser = require("body-parser");
const http = require("http");
const WebSocket = require("ws");
const Redis = require("ioredis");

// Redis setup
const redisPublisher = new Redis(process.env.REDISCLOUD_URL);
const redisSubscriber = new Redis(process.env.REDISCLOUD_URL);

redisPublisher.on("error", (err) => {
  console.error("Redis Publisher Error:", err);
});
redisSubscriber.on("error", (err) => {
  console.error("Redis Subscriber Error:", err);
});

const app = express();
const HTTP_PORT = process.env.PORT || 8080;

// Middleware
app.use(bodyParser.json());

// Function to publish file changes
const publishDBChange = (message) => {
  redisPublisher.publish("db-change", JSON.stringify(message));
};

// Endpoint: Scan a card
app.post("/scan", async (req, res) => {
  console.log("Scan request received!");

  const { enteredKey } = req.body;

  try {
    const validCards = await redisPublisher.smembers("validCards");
    const isValid = validCards.includes(enteredKey);

    // Log the scan in Redis history
    const newEntry = {
      enteredKey,
      success: isValid,
      time: new Date().toISOString(),
    };

    await redisPublisher.lpush("scanHistory", JSON.stringify(newEntry)); // Add scan to history
    await redisPublisher.ltrim("scanHistory", 0, 49); // Limit history to 50 entries

    publishDBChange({
      event: "new-scan",
      newEntry,
    });

    res
      .status(isValid ? 200 : 401)
      .send(isValid ? "Access granted!" : "Access denied!");
  } catch (error) {
    console.error("Error processing scan:", error);
    res.status(500).send("Internal server error.");
  }
});

// Endpoint: Add a new valid card
app.post("/add-card", async (req, res) => {
  const { newKeyCode } = req.body;
  if (!newKeyCode) {
    return res.status(400).send("Card is required.");
  }

  try {
    const exists = await redisPublisher.sismember("validCards", newKeyCode);
    if (exists) {
      return res.status(400).send("Card already exists.");
    }

    await redisPublisher.sadd("validCards", newKeyCode); // Add the card to the Redis set
    console.log("Card added successfully:", newKeyCode);
    res.status(200).send("Card added successfully!");
  } catch (error) {
    console.error("Error adding card:", error);
    res.status(500).send("Internal server error.");
  }
});

// Fetch all valid cards
app.get("/valid-cards", async (req, res) => {
  try {
    const validCards = await redisPublisher.smembers("validCards"); // Get all cards from the Redis set
    res.status(200).json(validCards);
  } catch (error) {
    console.error("Error fetching valid cards:", error);
    res.status(500).send("Internal server error.");
  }
});

// Delete a valid card
app.delete("/delete-card", async (req, res) => {
  const { card } = req.body;
  if (!card) {
    return res.status(400).send("Card is required.");
  }

  try {
    const removed = await redisPublisher.srem("validCards", card); // Remove the card from the Redis set
    if (removed) {
      res.status(200).send(`Card '${card}' deleted successfully.`);
    } else {
      res.status(404).send("Card not found.");
    }
  } catch (error) {
    console.error("Error deleting card:", error);
    res.status(500).send("Internal server error.");
  }
});

// Endpoint: Get scan history
app.get("/scan-history", async (req, res) => {
  try {
    const history = await redisPublisher.lrange("scanHistory", 0, 49); // Fetch the last 50 scans
    const parsedHistory = history.map((entry) => JSON.parse(entry));
    res.status(200).json(parsedHistory);
  } catch (error) {
    console.error("Error fetching scan history:", error);
    res.status(500).send("Internal server error.");
  }
});

// WebSocket server setup
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

wss.on("connection", (ws) => {
  console.log("WebSocket client connected!");

  // Subscribe to Redis channel
  redisSubscriber.subscribe("db-change", (err) => {
    if (err) {
      console.error("Failed to subscribe to db-change channel:", err);
      ws.close(1011, "Subscription error");
    } else {
      console.log("Client subscribed to db-change channel.");
    }
  });

  // Handle Redis messages
  redisSubscriber.on("message", (channel, message) => {
    if (channel === "db-change" && ws.readyState === WebSocket.OPEN) {
      console.log("Sending message to client:", message);
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
    redisSubscriber.unsubscribe("db-change");
  });

  ws.on("error", (error) => {
    console.error("WebSocket error:", error);
    ws.terminate();
  });
});

// Start the server
server.listen(HTTP_PORT, () => {
  console.log(`Server running on port ${HTTP_PORT}`);
});
