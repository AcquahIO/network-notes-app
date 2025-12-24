import express from 'express';
import morgan from 'morgan';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import authRoutes from './routes/auth.js';
import sessionsRoutes from './routes/sessions.js';
import studyRoutes from './routes/study.js';
import shareRoutes from './routes/shares.js';

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json({ limit: '200mb' }));
app.use(morgan('dev'));

const __dirname = path.dirname(fileURLToPath(import.meta.url));
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.use('/api/auth', authRoutes);
app.use('/api/sessions', sessionsRoutes);
app.use('/api/study', studyRoutes);
app.use('/api/shares', shareRoutes);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ message: 'Unexpected server error' });
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Conference Note AI backend running on ${PORT}`));
