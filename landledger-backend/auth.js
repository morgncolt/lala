const admin = require("firebase-admin");  // Import Firebase Admin SDK
const path = require("path");
const jwt = require("jsonwebtoken");  // Import JWT for token generation
const express = require("express");
const authMiddleware = require("./middleware/authMiddleware"); // Ensure JWT authentication

const router = express.Router();

// Correctly load the Firebase Admin SDK JSON
const serviceAccount = require(path.join(__dirname, "firebase-config.json"));

// Initialize Firebase Admin SDK with service account credentials (only once)
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

// Signup Route - Registers a new user
router.post("/signup", async (req, res) => {
    const { email, password, name } = req.body;  // Extract user input
    try {
        // Create user in Firebase Auth
        const user = await admin.auth().createUser({ email, password, displayName: name });
        // Generate a JWT token for the user
        const token = jwt.sign({ uid: user.uid }, process.env.JWT_SECRET, { expiresIn: "7d" });
        res.json({ token, user });  // Return token and user data
    } catch (error) {
        res.status(500).json({ error: error.message });  // Handle errors
    }
});

// Login Route - Authenticates a user using Firebase Custom Token
router.post("/login", async (req, res) => {
    const { email } = req.body;  // Extract user email (password verification is done on frontend)
    try {
        // Retrieve user by email from Firebase Auth
        const user = await admin.auth().getUserByEmail(email);

        // Generate a JWT token for the user
        const token = jwt.sign({ uid: user.uid }, process.env.JWT_SECRET, { expiresIn: "7d" });

        res.json({ token, user });  // Return token and user data
    } catch (error) {
        res.status(500).json({ error: "Invalid email or password" });  // Handle errors
    }
});

// Update User Display Name in Firebase
router.put("/update-name", authMiddleware, async (req, res) => {
    const { name } = req.body;
    const uid = req.user.uid; // Extracted from the JWT token

    try {
        // Update Firebase Authentication user profile
        await admin.auth().updateUser(uid, { displayName: name });

        res.json({ message: "User name updated successfully" });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;
