const express = require('express');
const amqp = require('amqplib');
const Redis = require('ioredis');
const { Client } = require('pg');

const app = express();
const PORT = 3000;

// Redis client (K8s service name: redis)
const redis = new Redis({ host: 'redis', port: 6379 });

// PostgreSQL client (K8s service name: postgres-service)
const pgClient = new Client({
  host: 'postgres-service',
  port: 5432,
  user: 'myuser',
  password: 'mypass',
  database: 'mydb'
});

pgClient.connect()
  .then(() => console.log('[✓] Connected to PostgreSQL'))
  .catch(err => console.error('[✗] PostgreSQL connection error:', err.message));

// RabbitMQ setup (K8s service name: rabbitmq)
let channel, connection;

async function connectToRabbitMQ(retries = 10) {
  while (retries) {
    try {
      connection = await amqp.connect('amqp://user:pass@rabbitmq.lra-poc.svc.cluster.local:5672');
      channel = await connection.createChannel();
      await channel.assertQueue('test-queue');
      console.log('[✓] Connected to RabbitMQ');

      // Consume messages
      channel.consume('test-queue', msg => {
        const content = msg.content.toString();
        console.log(`[→] Received from RabbitMQ: ${content}`);
        channel.ack(msg);
      });

      return;
    } catch (err) {
      console.error(`[✗] RabbitMQ connection error: ${err.message}. Retrying in 3s...`);
      retries--;
      await new Promise(res => setTimeout(res, 3000));
    }
  }
  process.exit(1);
}

connectToRabbitMQ();

// Health check
app.get('/', (req, res) => {
  res.send('✅ Backend is running and connected');
});

// Redis Set
app.get('/set', async (req, res) => {
  try {
    await redis.set('mykey', 'Hello from Redis!');
    res.send('✅ Key set in Redis');
  } catch (err) {
    console.error('[✗] Redis SET error:', err.message);
    res.status(500).send('Redis error');
  }
});

// Redis Get
app.get('/get', async (req, res) => {
  try {
    const value = await redis.get('mykey');
    res.send(`Value from Redis: ${value}`);
  } catch (err) {
    console.error('[✗] Redis GET error:', err.message);
    res.status(500).send('Redis error');
  }
});

// PostgreSQL test
app.get('/dbtest', async (req, res) => {
  try {
    await pgClient.query(`CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, message TEXT)`);
    await pgClient.query(`INSERT INTO test_table (message) VALUES ('Hello from PostgreSQL!')`);
    const result = await pgClient.query(`SELECT * FROM test_table`);
    res.json(result.rows);
  } catch (err) {
    console.error('[✗] PostgreSQL error:', err.
