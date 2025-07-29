import dotenv from 'dotenv';
dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000'),
  nodeEnv: process.env.NODE_ENV || 'development',
  db: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'ironclad_db',
    user: process.env.DB_USER || 'ironclad_user',
    password: process.env.DB_PASSWORD || 'ironclad_pass'
  },
  metrics: {
    port: parseInt(process.env.METRICS_PORT || '9090')
  },
  rateLimiting: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100 // limit each IP to 100 requests per windowMs
  }
};