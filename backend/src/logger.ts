import winston from 'winston';
import { config } from './config';

export const logger = winston.createLogger({
  level: config.nodeEnv === 'production' ? 'info' : 'debug',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: { 
    service: 'ironclad-sre-demo',
    version: '1.0.0',
    environment: config.nodeEnv
  },
  transports: [
    new winston.transports.Console({
      format: config.nodeEnv === 'production' 
        ? winston.format.json()
        : winston.format.combine(
            winston.format.colorize(),
            winston.format.simple()
          )
    })
  ]
});