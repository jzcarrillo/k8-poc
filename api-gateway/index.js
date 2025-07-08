const express = require('express');
const rateLimit = require('express-rate-limit');
const { createProxyMiddleware } = require('http-proxy-middleware');
const client = require('prom-client');

const app = express();
const PORT = 8081;
const FRONTEND = 'http://localhost:80';

// === Metrics ===
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const totalRequests = new client.Counter({
  name: 'api_gateway_requests_total',
  help: 'Total number of requests to API Gateway',
  labelNames: ['route', 'method'],
});
const throttledRequests = new client.Counter({
  name: 'api_gateway_429_total',
  help: 'Total number of 429 responses',
  labelNames: ['route'],
});
register.registerMetric(totalRequests);
register.registerMetric(throttledRequests);

// === Middleware ===
app.use(express.json());
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', FRONTEND);
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});
app.use((req, res, next) => {
  totalRequests.inc({ route: req.path, method: req.method });
  next();
});

// === Health and metrics
app.get('/', (req, res) => res.send('✅ API Gateway UP'));
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// === Rate limiter
const submitLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  handler: (req, res) => {
    throttledRequests.inc({ route: '/submit' });
    res.status(429).json({ message: '⚠️ Too many requests to /submit' });
  },
});

// === Proxy with fixed body forwarding
app.use(
  '/submit',
  (req, res, next) => {
    console.log(`[LOG] Incoming ${req.method} request to ${req.originalUrl}`);
    next();
  },
  submitLimiter,
  createProxyMiddleware({
    target: 'http://lambda-producer-service:4000',
    changeOrigin: true,
    selfHandleResponse: false, // default
    onProxyReq: (proxyReq, req, res) => {
      if (req.body) {
        const bodyData = JSON.stringify(req.body);
        proxyReq.setHeader('Content-Type', 'application/json');
        proxyReq.setHeader('Content-Length', Buffer.byteLength(bodyData));
        proxyReq.write(bodyData);
        // ❌ NEVER do proxyReq.end()
      }
      console.log(`[→] Forwarding to: ${req.originalUrl}`);
    },
    onProxyRes: (proxyRes, req, res) => {
      proxyRes.headers['Access-Control-Allow-Origin'] = FRONTEND;
      console.log(`[✅ SUCCESS] ${req.method} ${req.originalUrl} ← ${proxyRes.statusCode}`);
    },
    onError: (err, req, res) => {
      console.error(`[❌ ERROR] ${req.method} ${req.originalUrl} → lambda-producer-service`);
      console.error(`[❌ ERROR] ${err.message}`);
      res.status(500).send('Proxy error: ' + err.message);
    }
  })
);

// === Start server
app.listen(PORT, () => {
  console.log(`✅ API Gateway running on port ${PORT}`);
});
