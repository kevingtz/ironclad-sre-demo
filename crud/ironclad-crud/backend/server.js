const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// Database connection
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: 5432,
  database: process.env.DB_NAME || 'ironclad_db',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres'
});

// Initialize database
async function initDB() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        first_name VARCHAR(100) NOT NULL CHECK (first_name ~ '^[A-Za-z\\s-]+$'),
        middle_name VARCHAR(100),
        last_name VARCHAR(100) NOT NULL CHECK (last_name ~ '^[A-Za-z\\s-]+$'),
        email VARCHAR(255) UNIQUE NOT NULL,
        phone_number VARCHAR(20) NOT NULL,
        date_of_birth DATE NOT NULL
      )
    `);
    console.log('Database initialized');
  } catch (err) {
    console.error('Database init error:', err);
  }
}

// Validation functions
function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function validatePhone(phone) {
  return /^(\+1|1)?[-.\s]?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}$/.test(phone);
}

function validateDate(dateStr) {
  const regex = /^(0[1-9]|1[0-2])\/(0[1-9]|[12]\d|3[01])\/\d{4}$/;
  if (!regex.test(dateStr)) return false;
  
  const [month, day, year] = dateStr.split('/').map(Number);
  const date = new Date(year, month - 1, day);
  return date <= new Date() && date.getDate() === day;
}

// CRUD Endpoints

// Create
app.post('/api/users', async (req, res) => {
  const { first_name, middle_name, last_name, email, phone_number, date_of_birth } = req.body;
  
  // Validation
  if (!validateEmail(email)) {
    return res.status(400).json({ error: 'Invalid email format' });
  }
  if (!validatePhone(phone_number)) {
    return res.status(400).json({ error: 'Invalid USA phone number format' });
  }
  if (!validateDate(date_of_birth)) {
    return res.status(400).json({ error: 'Invalid date format (MM/DD/YYYY required)' });
  }
  
  try {
    // Convert date format for PostgreSQL
    const [month, day, year] = date_of_birth.split('/');
    const pgDate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
    
    const result = await pool.query(
      'INSERT INTO users (first_name, middle_name, last_name, email, phone_number, date_of_birth) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
      [first_name, middle_name, last_name, email, phone_number, pgDate]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      res.status(400).json({ error: 'Email already exists' });
    } else {
      res.status(500).json({ error: err.message });
    }
  }
});

// Read
app.get('/api/users', async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT id, first_name, middle_name, last_name, email, phone_number, to_char(date_of_birth, 'MM/DD/YYYY') as date_of_birth FROM users ORDER BY id"
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update
app.put('/api/users/:id', async (req, res) => {
  const { id } = req.params;
  const { first_name, middle_name, last_name, email, phone_number, date_of_birth } = req.body;
  
  // Validation
  if (!validateEmail(email)) {
    return res.status(400).json({ error: 'Invalid email format' });
  }
  if (!validatePhone(phone_number)) {
    return res.status(400).json({ error: 'Invalid USA phone number format' });
  }
  if (!validateDate(date_of_birth)) {
    return res.status(400).json({ error: 'Invalid date format' });
  }
  
  try {
    const [month, day, year] = date_of_birth.split('/');
    const pgDate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
    
    const result = await pool.query(
      'UPDATE users SET first_name=$1, middle_name=$2, last_name=$3, email=$4, phone_number=$5, date_of_birth=$6 WHERE id=$7 RETURNING *',
      [first_name, middle_name, last_name, email, phone_number, pgDate, id]
    );
    
    if (result.rows.length === 0) {
      res.status(404).json({ error: 'User not found' });
    } else {
      res.json(result.rows[0]);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete
app.delete('/api/users/:id', async (req, res) => {
  const { id } = req.params;
  
  try {
    const result = await pool.query('DELETE FROM users WHERE id=$1 RETURNING id', [id]);
    
    if (result.rows.length === 0) {
      res.status(404).json({ error: 'User not found' });
    } else {
      res.status(204).send();
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Start server
const PORT = process.env.PORT || 3000;
initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
  });
});