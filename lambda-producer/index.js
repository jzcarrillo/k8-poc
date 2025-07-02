const express = require('express');
const amqp = require('amqplib');
const cors = require('cors');

const app = express();

// ✅ Proper CORS setup
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type']
}));

// ✅ Handle preflight requests
app.options('*', cors());

app.use(express.json());

// ✅ Log all incoming requests
app.use((req, res, next) => {
  console.log(`[REQ] ${req.method} ${req.url} - Body: ${JSON.stringify(req.body)}`);
  next();
});

let channel;
const QUEUE = 'test-queue';

// ✅ Use custom RabbitMQ credentials
const RABBITMQ_URL = 'amqp://myuser:mypass@rabbitmq.lra-poc.svc.cluster.local:5672';

/**
 * Connects to RabbitMQ with retry logic for K8s readiness delays
 */
async function connectRabbitMQ(retries = 10) {
  while (retries) {
    try {
      const connection = await amqp.connect(RABBITMQ_URL);
      channel = await connection.createChannel();
      await channel.assertQueue(QUEUE, { durable: true }); // durable queue
      console.log('[✓] Connected to RabbitMQ');
      return;
    } catch (err) {
      console.error(`[✗] RabbitMQ connection failed: ${err.message}. Retrying in 3 seconds...`);
      retries--;
      await new Promise(res => setTimeout(res, 3000));
    }
  }
  console.error('[✗] Could not connect to RabbitMQ after retries. Continuing without it.');
}

// ✅ Always start Express server even if RabbitMQ is not ready yet
const PORT = 4000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Lambda Producer running on port ${PORT}`);
});

// 🔁 Attempt RabbitMQ connection in background
connectRabbitMQ();

/**
 * POST /produce
 * Sends a message to RabbitMQ queue
 */
app.post('/produce', async (req, res) => {
  const { message } = req.body;

  if (!message) {
    return res.status(400).send('Message is required');
  }

  try {
    if (!channel) {
      console.error('[✗] RabbitMQ channel not ready');
      return res.status(503).send('RabbitMQ not ready');
    }

    channel.sendToQueue(QUEUE, Buffer.from(message), { persistent: true });
    console.log(`[→] Sent message: ${message}`);
    res.send('Message sent to RabbitMQ');
  } catch (err) {
    console.error('[✗] Failed to send message:', err.message);
    res.status(500).send('Failed to send message');
  }
});
