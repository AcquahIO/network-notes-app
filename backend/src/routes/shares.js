import express from 'express';
import { authenticate } from '../middleware/auth.js';
import { getSharePayload, importSharedSession } from '../services/shares.js';
import { query } from '../db.js';

const router = express.Router();

router.use(authenticate);

router.get('/:token', async (req, res) => {
  const { token } = req.params;
  try {
    const payload = await getSharePayload({ token });
    if (!payload) return res.status(404).json({ message: 'Share not found or expired' });
    res.json(payload);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to load share' });
  }
});

router.post('/:token/import', async (req, res) => {
  const { token } = req.params;
  try {
    const result = await importSharedSession({ token, userId: req.user.id });
    if (!result) return res.status(404).json({ message: 'Share not found or expired' });
    res.json({ session_id: result.newSessionId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to import share' });
  }
});

router.post('/:token/revoke', async (req, res) => {
  const { token } = req.params;
  try {
    const shareResult = await query('SELECT * FROM shares WHERE share_token = $1', [token]);
    const share = shareResult.rows[0];
    if (!share) return res.status(404).json({ message: 'Share not found' });
    if (share.owner_user_id !== req.user.id) return res.status(403).json({ message: 'Not authorized' });

    await query('UPDATE shares SET revoked = true WHERE share_token = $1', [token]);
    res.json({ message: 'Share revoked' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to revoke share' });
  }
});

export default router;
