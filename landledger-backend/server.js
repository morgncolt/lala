/*Express app is created and configured to accept JSON data.
CORS is enabled to allow frontend applications to communicate with the backend.
A test endpoint (/) returns a simple success message.*/



require("dotenv").config();  // Load environment variables
const express = require("express");
const cors = require("cors");
const authRoutes = require("./auth");  // Import authentication routes
const profileRoutes = require("./routes/profile") //Import profile routes

const mongoose = require("mongoose")
//connect to MongoDB


const app = express();
app.use(express.json());  // Middleware to parse JSON requests

mongoose.connect(process.env.MONGO_URI)
    .then(() => console.log("✅ MongoDB Connected"))
    .catch(err => console.error("❌ MongoDB Connection Error:", err));

app.use(cors());  // Enable CORS

// Debugging: Print environment variables
//console.log("Environment Variables Loaded: ", process.env);

app.use("/api", authRoutes); //Prefix API routes
app.use("/api", profileRoutes);  


app.get("/", (req, res) => {
    res.send("LandLedger Africa API is running...");
});

const PORT = process.env.PORT || 4000;  // Use environment variable or default to 4000
const HOST = '0.0.0.0';  // Listen on all network interfaces (allows connections from network devices)
//console.log(`PORT value: ${PORT}`);  // Debug: Check if PORT is loaded
app.listen(PORT, HOST, () => console.log(`Server running on http://${HOST}:${PORT}`));
