const amqp = require('amqplib');
const express = require('express');
const { Pool } = require('pg'); // ✅ PostgreSQL client

const QUEUE = 'test-queue';
const RABBITMQ_URL = 'amqp://myuser:mypass@rabbitmq.lra-poc.svc.cluster.local:5672';
const PORT = 4001;

// ✅ PostgreSQL configuration
const pool = new Pool({
  host: 'postgres-service.lra-poc.svc.cluster.local',
  port: 5432,
  user: 'myuser',
  password: 'mypass',
  database: 'mydb',
});

// ✅ Test DB connection at startup
pool.connect()
  .then(() => console.log('[✓] Connected to PostgreSQL'))
  .catch(err => {
    console.error('[✗] Failed to connect to PostgreSQL at startup:', err);
    process.exit(1);
  });

let channel;

async function connectConsumer(retries = 10) {
  while (retries) {
    try {
      const connection = await amqp.connect(RABBITMQ_URL);
      connection.on('error', (err) => {
        console.error('[✗] RabbitMQ connection error:', err.message);
        process.exit(1);
      });

      connection.on('close', () => {
        console.warn('[!] RabbitMQ connection closed. Exiting...');
        process.exit(1);
      });

      channel = await connection.createChannel();
      await channel.assertQueue(QUEUE, { durable: true });

      console.log('[✓] Connected to RabbitMQ and queue asserted');

      // ✅ Start consuming and insert to DB
      channel.consume(QUEUE, async (msg) => {
        if (msg !== null) {
          const content = msg.content.toString();
          console.log(`[←] Consumed message: ${content}`);

          try {
            await pool.query('INSERT INTO test_table (message) VALUES ($1)', [content]);
            console.log('[✓] Inserted to PostgreSQL');
          } catch (err) {
            console.error('[✗] Failed to insert into DB:', err); // full error
          }

          channel.ack(msg);
        }
      });

      return;
    } catch (err) {
      console.error(`[✗] RabbitMQ consumer connection failed: ${err.message}. Retrying in 3s...`);
      retries--;
      await new Promise((res) => setTimeout(res, 3000));
    }
  }

  console.error('[✗] Could not connect to RabbitMQ. Exiting.');
  process.exit(1);
}

connectConsumer();

// ✅ Health check endpoint
const app = express();

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'lambda-consumer' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[HTTP] Health endpoint running on port ${PORT}`);
});
