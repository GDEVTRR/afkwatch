'use strict';
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

/** In production reject plain-HTTP API calls (TLS is terminated by Render's proxy; trust proxy must be set). */
function requireHttps(isProd) {
  return (req, res, next) => {
    if (!isProd || req.path === '/healthz' || req.secure) return next();
    return res.status(426).json({ error: { code: 'HTTPS_REQUIRED', message: 'Use HTTPS' } });
  };
}

const limiter = (windowMs, limit) => rateLimit({
  windowMs, limit, standardHeaders: 'draft-7', legacyHeaders: false,
  message: { error: { code: 'RATE_LIMITED', message: 'Too many requests' } },
});

module.exports = { helmet: () => helmet(), requireHttps, limiter };
