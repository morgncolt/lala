const express = require("express");
const admin = require("firebase-admin");
const { body, validationResult } = require("express-validator");
const authMiddleware = require("../middleware/authMiddleware"); // Import JWT Middleware
const router = express.Router();

// Async Handler to Catch Errors
const asyncHandler = fn => (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
};

// 🔹 Update User Profile (Change Name)
router.put(
    "/profile",
    authMiddleware,
    body("name").isLength({ min: 1 }).withMessage("Name is required"), // Input validation
    asyncHandler(async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { name } = req.body;
        const uid = req.user.uid; // Extracted from JWT token

        // 🔹 Update Firebase Authentication user profile
        await admin.auth().updateUser(uid, { displayName: name });

        res.json({ message: "User name updated successfully", newName: name });
    })
);

// 🔹 Get User Profile (Requires JWT)
router.get(
    "/profile",
    authMiddleware,
    asyncHandler(async (req, res) => {
        const uid = req.user.uid; // Extracted from JWT token
        console.log("Fetching user profile for UID:", uid); // Debug log

        // 🔹 Retrieve user from Firebase Authentication
        const userRecord = await admin.auth().getUser(uid);
        console.log("User Record Retrieved:", userRecord); // Debug log

        res.json({
            uid: userRecord.uid,
            email: userRecord.email,
            name: userRecord.displayName || "No name set",
            createdAt: userRecord.metadata.creationTime,
            lastSignInTime: userRecord.metadata.lastSignInTime,
            customClaims: userRecord.customClaims || {},
        });
    })
);

module.exports = router;
