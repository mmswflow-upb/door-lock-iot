const mongoose = require("mongoose");

const scanHistorySchema = new mongoose.Schema({
  enteredKey: { type: String, required: true },
  success: { type: Boolean, required: true },
  time: { type: Date, default: Date.now },
});

module.exports = mongoose.model("Scan", scanHistorySchema, "Scans");
