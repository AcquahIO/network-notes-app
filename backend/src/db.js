import pg from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const { Pool } = pg;

const connectionString = process.env.DATABASE_URL || 'postgres://localhost:5432/conference_note_ai';

const pool = new Pool({
  connectionString,
  ssl: connectionString.includes('localhost') ? false : { rejectUnauthorized: false }
});

pool.on('error', (err) => {
  console.error('Unexpected database error', err);
});

export const query = (text, params) => pool.query(text, params);
export const getClient = () => pool.connect();
export default { query, getClient };
