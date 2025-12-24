import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';
import dotenv from 'dotenv';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL is not set. Add it to backend/.env before running migrations.');
  process.exit(1);
}

const migrationsDir = path.join(__dirname, '../migrations');

const runMigration = (filePath) =>
  new Promise((resolve, reject) => {
    const child = spawn('psql', [databaseUrl, '-f', filePath], { stdio: 'inherit' });
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`psql exited with code ${code ?? 1}`));
    });
    child.on('error', (err) => reject(err));
  });

try {
  const entries = await fs.readdir(migrationsDir);
  const migrations = entries.filter((file) => file.endsWith('.sql')).sort();
  if (!migrations.length) {
    console.error('No migration files found.');
    process.exit(1);
  }

  for (const migration of migrations) {
    console.log(`Running migration ${migration}...`);
    await runMigration(path.join(migrationsDir, migration));
  }

  console.log('Migrations complete.');
} catch (err) {
  console.error(`Failed to run migrations: ${err.message}`);
  process.exit(1);
}
