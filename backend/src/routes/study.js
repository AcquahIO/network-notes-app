import express from 'express';
import { authenticate } from '../middleware/auth.js';
import { query } from '../db.js';

const router = express.Router();

router.use(authenticate);

router.get('/', async (req, res) => {
  try {
    const sessions = await query(
      `SELECT s.id, s.title, s.status, s.started_at, s.duration_seconds,
              COALESCE((SELECT COUNT(*) FROM photos p WHERE p.session_id = s.id), 0) AS photo_count,
              COALESCE((SELECT COUNT(*) FROM resources r WHERE r.session_id = s.id), 0) AS resource_count,
              (SELECT short_summary FROM summaries sm WHERE sm.session_id = s.id) AS summary
       FROM sessions s
       WHERE s.user_id = $1 AND s.status = 'ready'
       ORDER BY s.started_at DESC`,
      [req.user.id]
    );
    res.json(sessions.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to load study sessions' });
  }
});

export default router;
