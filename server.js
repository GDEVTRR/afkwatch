require("dotenv").config();

const express = require("express");
const http = require("http");
const cors = require("cors");
const helmet = require("helmet");
const multer = require("multer");
const QRCode = require("qrcode");
const Database = require("better-sqlite3");
const { Server } = require("socket.io");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const app = express();
const server = http.createServer(app);

const PORT = Number(process.env.PORT || 3000);
const PUBLIC_URL = (process.env.PUBLIC_URL || `http://localhost:${PORT}`).replace(/\/$/, "");
const DB_PATH = path.resolve(process.env.DATABASE_PATH || "./data/afkwatch.db");
const STORAGE = path.resolve(process.env.SCREENSHOT_DIR || "./data/screenshots");
const MAX_SIZE = Number(process.env.MAX_SCREENSHOT_MB || 15) * 1024 * 1024;
const PAIRING_TTL = Number(process.env.PAIRING_TTL_SECONDS || 300) * 1000;

fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
fs.mkdirSync(STORAGE, { recursive: true });

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || "*" }));
app.use(express.json({ limit: "1mb" }));

const io = new Server(server, {
    cors: {
        origin: process.env.CORS_ORIGIN || "*",
        methods: ["GET", "POST", "DELETE"]
    },
    maxHttpBufferSize: MAX_SIZE
});

// DATABASE

const db = new Database(DB_PATH);

db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

db.exec(`
CREATE TABLE IF NOT EXISTS pairings (
    id TEXT PRIMARY KEY,
    desktop_hash TEXT NOT NULL,
    phone_hash TEXT,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS screenshots (
    id TEXT PRIMARY KEY,
    pair_id TEXT NOT NULL,
    filename TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size INTEGER NOT NULL,
    window_title TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY(pair_id) REFERENCES pairings(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_screenshots_pair
ON screenshots(pair_id, created_at DESC);
`);

// HELPERS

function id() {
    return crypto.randomUUID();
}

function token() {
    return crypto.randomBytes(32).toString("base64url");
}

function hash(value) {
    return crypto.createHash("sha256").update(value).digest("hex");
}

function findDevice(value) {
    if (!value || typeof value !== "string") return null;

    const hashed = hash(value);

    return db.prepare(`
        SELECT id, 'desktop' AS role
        FROM pairings
        WHERE desktop_hash = ?

        UNION ALL

        SELECT id, 'phone' AS role
        FROM pairings
        WHERE phone_hash = ?

        LIMIT 1
    `).get(hashed, hashed) || null;
}

function authenticate(role) {
    return (req, res, next) => {
        const header = req.headers.authorization || "";
        const accessToken = header.startsWith("Bearer ")
            ? header.slice(7)
            : null;

        const device = findDevice(accessToken);

        if (!device) {
            return res.status(401).json({
                success: false,
                error: "UNAUTHORIZED"
            });
        }

        if (role && device.role !== role) {
            return res.status(403).json({
                success: false,
                error: "FORBIDDEN"
            });
        }

        req.device = device;
        next();
    };
}

function getFile(filename) {
    if (!/^[a-f0-9-]+\.bin$/i.test(filename)) return null;

    return path.join(STORAGE, filename);
}

function removeScreenshot(row) {
    if (!row) return;

    const file = getFile(row.filename);

    if (file && fs.existsSync(file)) {
        fs.unlinkSync(file);
    }

    db.prepare("DELETE FROM screenshots WHERE id = ?").run(row.id);
}

// PAIRING

const pendingPairs = new Map();

function cleanPairs() {
    const now = Date.now();

    for (const [code, pair] of pendingPairs) {
        if (pair.expiresAt <= now) {
            pendingPairs.delete(code);

            db.prepare(`
                DELETE FROM pairings
                WHERE id = ? AND phone_hash IS NULL
            `).run(pair.pairId);
        }
    }
}

app.post("/api/pairing/create", async (req, res) => {
    try {
        cleanPairs();

        const pairId = id();
        const desktopToken = token();
        const code = token();
        const expiresAt = Date.now() + PAIRING_TTL;

        db.prepare(`
            INSERT INTO pairings
            (id, desktop_hash, phone_hash, created_at)
            VALUES (?, ?, NULL, ?)
        `).run(pairId, hash(desktopToken), Date.now());

        pendingPairs.set(code, {
            pairId,
            expiresAt
        });

        const qrPayload = JSON.stringify({
            type: "AFK_WATCH_PAIR",
            version: 1,
            server: PUBLIC_URL,
            code
        });

        const qr = await QRCode.toDataURL(qrPayload, {
            width: 320,
            margin: 2
        });

        res.json({
            success: true,
            pairId,
            desktopToken,
            qr,
            expiresAt
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({
            success: false,
            error: "PAIR_CREATE_FAILED"
        });
    }
});

app.post("/api/pairing/claim", (req, res) => {
    try {
        cleanPairs();

        const code = req.body?.code;

        if (typeof code !== "string") {
            return res.status(400).json({
                success: false,
                error: "INVALID_CODE"
            });
        }

        const pairing = pendingPairs.get(code);

        if (!pairing) {
            return res.status(410).json({
                success: false,
                error: "QR_EXPIRED_OR_USED"
            });
        }

        const phoneToken = token();

        const result = db.prepare(`
            UPDATE pairings
            SET phone_hash = ?
            WHERE id = ? AND phone_hash IS NULL
        `).run(hash(phoneToken), pairing.pairId);

        if (result.changes !== 1) {
            pendingPairs.delete(code);

            return res.status(409).json({
                success: false,
                error: "ALREADY_PAIRED"
            });
        }

        // QR is single-use.
        pendingPairs.delete(code);

        io.to(`desktop:${pairing.pairId}`).emit("pair:completed", {
            pairId: pairing.pairId
        });

        res.json({
            success: true,
            pairId: pairing.pairId,
            phoneToken
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({
            success: false,
            error: "PAIR_FAILED"
        });
    }
});

// DEVICE STATUS

app.get("/api/device", authenticate(), (req, res) => {
    const pairing = db.prepare(`
        SELECT phone_hash
        FROM pairings
        WHERE id = ?
    `).get(req.device.id);

    res.json({
        success: true,
        pairId: req.device.id,
        role: req.device.role,
        paired: !!pairing?.phone_hash
    });
});

// SCREENSHOT UPLOAD

const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
        fileSize: MAX_SIZE,
        files: 1
    },
    fileFilter(req, file, callback) {
        const allowed = [
            "image/jpeg",
            "image/png",
            "image/webp"
        ];

        callback(
            allowed.includes(file.mimetype)
                ? null
                : new Error("INVALID_IMAGE_TYPE"),
            allowed.includes(file.mimetype)
        );
    }
});

app.post(
    "/api/screenshots",
    authenticate("desktop"),
    upload.single("screenshot"),
    (req, res) => {
        try {
            if (!req.file) {
                return res.status(400).json({
                    success: false,
                    error: "SCREENSHOT_REQUIRED"
                });
            }

            const screenshotId = id();
            const filename = `${screenshotId}.bin`;
            const filePath = getFile(filename);

            const windowTitle = String(
                req.body.windowTitle || ""
            ).slice(0, 300);

            fs.writeFileSync(filePath, req.file.buffer, {
                flag: "wx"
            });

            try {
                db.prepare(`
                    INSERT INTO screenshots
                    (id, pair_id, filename, mime_type, size, window_title, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                `).run(
                    screenshotId,
                    req.device.id,
                    filename,
                    req.file.mimetype,
                    req.file.size,
                    windowTitle,
                    Date.now()
                );
            } catch (error) {
                fs.unlinkSync(filePath);
                throw error;
            }

            const item = {
                id: screenshotId,
                windowTitle,
                mimeType: req.file.mimetype,
                size: req.file.size,
                createdAt: Date.now()
            };

            io.to(`phone:${req.device.id}`).emit("screenshot:new", item);

            res.status(201).json({
                success: true,
                screenshot: item
            });

        } catch (error) {
            console.error(error);
            res.status(500).json({
                success: false,
                error: "UPLOAD_FAILED"
            });
        }
    }
);

// PHONE: PENDING SCREENSHOTS

app.get(
    "/api/screenshots/pending",
    authenticate("phone"),
    (req, res) => {
        const items = db.prepare(`
            SELECT id, window_title, mime_type, size, created_at
            FROM screenshots
            WHERE pair_id = ?
            ORDER BY created_at ASC
        `).all(req.device.id);

        res.json({
            success: true,
            screenshots: items.map(item => ({
                id: item.id,
                windowTitle: item.window_title,
                mimeType: item.mime_type,
                size: item.size,
                createdAt: item.created_at
            }))
        });
    }
);

// PHONE: DOWNLOAD SCREENSHOT

app.get(
    "/api/screenshots/:id/file",
    authenticate("phone"),
    (req, res) => {
        const item = db.prepare(`
            SELECT *
            FROM screenshots
            WHERE id = ? AND pair_id = ?
        `).get(req.params.id, req.device.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                error: "NOT_FOUND"
            });
        }

        const file = getFile(item.filename);

        if (!file || !fs.existsSync(file)) {
            return res.status(410).json({
                success: false,
                error: "FILE_EXPIRED"
            });
        }

        res.setHeader("Content-Type", item.mime_type);
        res.setHeader(
            "Content-Disposition",
            `attachment; filename="${item.id}.jpg"`
        );

        fs.createReadStream(file).pipe(res);
    }
);

// PHONE: ACKNOWLEDGE DELIVERY
// Call only AFTER saving the image locally.

app.post(
    "/api/screenshots/:id/ack",
    authenticate("phone"),
    (req, res) => {
        const item = db.prepare(`
            SELECT *
            FROM screenshots
            WHERE id = ? AND pair_id = ?
        `).get(req.params.id, req.device.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                error: "NOT_FOUND"
            });
        }

        removeScreenshot(item);

        res.json({
            success: true,
            delivered: true,
            deletedFromCloud: true
        });
    }
);

// PHONE: DELETE PENDING SCREENSHOT

app.delete(
    "/api/screenshots/:id",
    authenticate("phone"),
    (req, res) => {
        const item = db.prepare(`
            SELECT *
            FROM screenshots
            WHERE id = ? AND pair_id = ?
        `).get(req.params.id, req.device.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                error: "NOT_FOUND"
            });
        }

        removeScreenshot(item);

        res.json({ success: true });
    }
);

// SOCKET AUTHENTICATION

io.use((socket, next) => {
    const accessToken = socket.handshake.auth?.token;
    const device = findDevice(accessToken);

    if (!device) {
        return next(new Error("UNAUTHORIZED"));
    }

    socket.device = device;
    next();
});

io.on("connection", socket => {
    const { id: pairId, role } = socket.device;

    socket.join(`${role}:${pairId}`);

    console.log(`[SOCKET] ${role} connected: ${pairId}`);

    socket.emit("connection:ready", {
        pairId,
        role
    });

    if (role === "phone") {
        const items = db.prepare(`
            SELECT id, window_title, mime_type, size, created_at
            FROM screenshots
            WHERE pair_id = ?
            ORDER BY created_at ASC
        `).all(pairId);

        socket.emit("screenshots:pending", items.map(item => ({
            id: item.id,
            windowTitle: item.window_title,
            mimeType: item.mime_type,
            size: item.size,
            createdAt: item.created_at
        })));
    }

    socket.on("disconnect", () => {
        console.log(`[SOCKET] ${role} disconnected: ${pairId}`);
    });
});

// DISCONNECT / UNPAIR

app.delete("/api/pairing", authenticate(), (req, res) => {
    const pairId = req.device.id;

    const pairing = db.prepare(`
        SELECT id FROM pairings WHERE id = ?
    `).get(pairId);

    if (!pairing) {
        return res.status(404).json({
            success: false,
            error: "PAIRING_NOT_FOUND"
        });
    }

    const files = db.prepare(`
        SELECT filename FROM screenshots WHERE pair_id = ?
    `).all(pairId);

    for (const item of files) {
        const file = getFile(item.filename);

        if (file && fs.existsSync(file)) {
            fs.unlinkSync(file);
        }
    }

    db.prepare("DELETE FROM pairings WHERE id = ?").run(pairId);

    io.to(`desktop:${pairId}`).emit("pair:revoked");
    io.to(`phone:${pairId}`).emit("pair:revoked");

    res.json({
        success: true,
        disconnected: true
    });
});

// ERRORS

app.use((error, req, res, next) => {
    console.error("[ERROR]", error.message);

    if (error.code === "LIMIT_FILE_SIZE") {
        return res.status(413).json({
            success: false,
            error: "FILE_TOO_LARGE"
        });
    }

    if (error.message === "INVALID_IMAGE_TYPE") {
        return res.status(415).json({
            success: false,
            error: "INVALID_IMAGE_TYPE"
        });
    }

    res.status(500).json({
        success: false,
        error: "INTERNAL_SERVER_ERROR"
    });
});

// HEALTH CHECK

app.get("/health", (req, res) => {
    res.status(200).json({
        ok: true,
        service: "AFKWatch",
        status: "online",
        timestamp: new Date().toISOString()
    });
});

// START

server.listen(PORT, () => {
    console.log("--------------------------------");
    console.log("       AFK WATCH CLOUD");
    console.log("--------------------------------");
    console.log(`Server: ${PUBLIC_URL}`);
    console.log(`Port: ${PORT}`);
    console.log("Database: Connected");
    console.log("Storage: Ready");
    console.log("Web interface: Disabled");
    console.log("--------------------------------");
});

process.on("SIGTERM", () => {
    console.log("Shutting down...");

    io.close();
    db.close();
    server.close(() => process.exit(0));
});
