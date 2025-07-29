import Joi from 'joi';
import { Request, Response, NextFunction } from 'express';

const userSchema = Joi.object({
  first_name: Joi.string()
    .pattern(/^[A-Za-z\s-]+$/)
    .max(100)
    .required()
    .messages({
      'string.pattern.base': 'First name can only contain letters, spaces, and hyphens'
    }),
  middle_name: Joi.string()
    .pattern(/^[A-Za-z\s-]*$/)
    .max(100)
    .allow('')
    .optional(),
  last_name: Joi.string()
    .pattern(/^[A-Za-z\s-]+$/)
    .max(100)
    .required()
    .messages({
      'string.pattern.base': 'Last name can only contain letters, spaces, and hyphens'
    }),
  email: Joi.string()
    .email()
    .max(255)
    .required(),
  phone_number: Joi.string()
    .pattern(/^(\+1|1)?[-.\s]?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}$/)
    .required()
    .messages({
      'string.pattern.base': 'Invalid US phone number format'
    }),
  date_of_birth: Joi.string()
    .pattern(/^(0[1-9]|1[0-2])\/(0[1-9]|[12]\d|3[01])\/\d{4}$/)
    .required()
    .custom((value, helpers) => {
      const [month, day, year] = value.split('/').map(Number);
      const date = new Date(year, month - 1, day);
      
      if (date > new Date()) {
        return helpers.error('date.future');
      }
      
      if (date.getFullYear() !== year || 
          date.getMonth() !== month - 1 || 
          date.getDate() !== day) {
        return helpers.error('date.invalid');
      }
      
      return value;
    })
    .messages({
      'string.pattern.base': 'Date must be in MM/DD/YYYY format',
      'date.future': 'Date of birth cannot be in the future',
      'date.invalid': 'Invalid date'
    })
});

export function validateUser(req: Request, res: Response, next: NextFunction) {
  const { error, value } = userSchema.validate(req.body, { abortEarly: false });
  
  if (error) {
    return res.status(400).json({
      error: 'Validation failed',
      details: error.details.map(d => ({
        field: d.path.join('.'),
        message: d.message
      }))
    });
  }
  
  req.body = value;
  next();
}