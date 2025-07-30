import { Pool } from 'pg';
import { config } from './config';
import { logger } from './logger';

export const pool = new Pool({
  host: config.db.host,
  port: config.db.port,
  database: config.db.database,
  user: config.db.user,
  password: config.db.password,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

export async function initDatabase() {
  try {
    // Create table if not exists
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        first_name VARCHAR(100) NOT NULL CHECK (first_name ~ '^[A-Za-z\\s-]+$'),
        middle_name VARCHAR(100) CHECK (middle_name IS NULL OR middle_name ~ '^[A-Za-z\\s-]*$'),
        last_name VARCHAR(100) NOT NULL CHECK (last_name ~ '^[A-Za-z\\s-]+$'),
        email VARCHAR(255) UNIQUE NOT NULL,
        phone_number VARCHAR(20) NOT NULL,
        date_of_birth DATE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Create index for performance
    await pool.query('CREATE INDEX IF NOT EXISTS idx_email ON users(email)');
    await pool.query('CREATE INDEX IF NOT EXISTS idx_created_at ON users(created_at DESC)');

    // Create update trigger
    await pool.query(`
      CREATE OR REPLACE FUNCTION update_updated_at_column()
      RETURNS TRIGGER AS $$
      BEGIN
          NEW.updated_at = CURRENT_TIMESTAMP;
          RETURN NEW;
      END;
      $$ language 'plpgsql';
    `);

    await pool.query(`
      DROP TRIGGER IF EXISTS update_users_updated_at ON users;
    `);
    
    await pool.query(`
      CREATE TRIGGER update_users_updated_at BEFORE UPDATE
          ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    `);

    logger.info('Database initialized successfully');
  } catch (error) {
    logger.error('Database initialization failed', error);
    throw error;
  }
}

export async function checkDatabaseHealth(): Promise<boolean> {
  try {
    const result = await pool.query('SELECT 1');
    return result.rows.length > 0;
  } catch {
    return false;
  }
}