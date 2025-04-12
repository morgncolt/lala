const jwt = require("jsonwebtoken");

module.exports = (req, res, next) => {
    const token = req.headers.authorization;
    
    if (!token) {
        return res.status(403).json({ error: "Unauthorized: No token provided" });
    }

    try {
        const decoded = jwt.verify(token.split(" ")[1], process.env.JWT_SECRET);
        req.user = decoded;  // Attach user info to request
        next();  // Proceed to the next middleware/route
    } catch (error) {
        res.status(401).json({ error: "Unauthorized: Invalid token" });
    }
};
