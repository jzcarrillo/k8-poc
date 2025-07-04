const express = require('express');
const rateLimit = require('express-rate-limit');
const { createProxyMiddleware } = require('http-proxy-middleware');
const client = require('prom-client');

const app = express();
const PORT = 8081;
const FRONTEND = 'https://vigilant-space-guide-v65wvgjx5ppqcxxr-443.app.github.dev';

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

// === Health Check and Metrics ===
app.get('/', (req, res) => res.send('✅ API Gateway UP'));
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// === Route: /submit → lambda-producer only ===
const submitLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  handler: (req, res) => {
    throttledRequests.inc({ route: '/submit' });
    res.status(429).json({ message: '⚠️ Too many requests to /submit' });
  },
});

app.use(
  '/submit',
  submitLimiter,
  createProxyMiddleware({
    target: 'http://lambda-producer:8081',
    changeOrigin: true,
    onProxyRes(proxyRes) {
      proxyRes.headers['Access-Control-Allow-Origin'] = FRONTEND;
    },
  })
);

app.listen(PORT, () => {
  console.log(`✅ API Gateway running on port ${PORT}`);
});