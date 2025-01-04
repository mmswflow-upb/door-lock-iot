const mongoose = require("mongoose");

const validCardSchema = new mongoose.Schema({
  card: { type: String, required: true, unique: true },
});

module.exports = mongoose.model("ValidCard", validCardSchema);
