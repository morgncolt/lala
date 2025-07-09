const mongoose = require("mongoose");

// Define User Schema
const UserSchema = new mongoose.Schema({
    uid: { type: String, required: true, unique: true },  // Firebase UID
    email: { type: String, required: true, unique: true },
    name: { type: String, required: true },
    createdAt: { type: Date, default: Date.now }
});

// Export the User Model
module.exports = mongoose.model("User", UserSchema);
