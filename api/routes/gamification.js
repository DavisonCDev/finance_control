// Gamificação, conquistas e desafios (spec §43).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const gamification = require('../lib/gamification');
const scope = require('../lib/scope');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const [[streak]] = await db.query('SELECT * FROM user_streaks WHERE user_id = ?', [req.userId]);
  const [achievements] = await db.query(
    `SELECT a.*, COALESCE(ua.progress, 0) AS progress, ua.earned_at
     FROM achievements a
     LEFT JOIN user_achievements ua ON ua.achievement_code = a.code AND ua.user_id = ?
     ORDER BY a.points DESC`,
    [req.userId]
  );
  const totalPoints = achievements.filter(a => a.earned_at).reduce((s, a) => s + a.points, 0);
  const earnedCount = achievements.filter(a => a.earned_at).length;
  const next = achievements.filter(a => !a.earned_at).sort((a, b) => Number(b.progress) - Number(a.progress)).slice(0, 3);
  res.json({
    streak: streak || { current_streak: 0, longest_streak: 0, total_points: 0 },
    achievements,
    total_points: totalPoints,
    earned_count: earnedCount,
    next_achievements: next
  });
}));

router.post('/recalculate', asyncHandler(async (req, res) => {
  const [tx] = await db.query('SELECT COUNT(*) AS c FROM transactions WHERE user_id = ? AND deleted_at IS NULL', [req.userId]);
  const [investments] = await db.query('SELECT COUNT(*) AS c FROM investments WHERE user_id = ?', [req.userId]);
  const [goals] = await db.query('SELECT COUNT(*) AS c FROM goals WHERE user_id = ? AND status = "completed"', [req.userId]);
  const [debts] = await db.query('SELECT COUNT(*) AS c FROM debts WHERE user_id = ? AND status != "paid"', [req.userId]);
  const [allDebts] = await db.query('SELECT COUNT(*) AS c FROM debts WHERE user_id = ?', [req.userId]);
  const [streak] = await db.query('SELECT * FROM user_streaks WHERE user_id = ?', [req.userId]);
  if (tx[0].c > 0) await gamification.grantAchievement(req.userId, 'first_transaction', tx[0].c);
  if (investments[0].c > 0) await gamification.grantAchievement(req.userId, 'first_investment', investments[0].c);
  if (goals[0].c > 0) await gamification.grantAchievement(req.userId, 'goal_completed', goals[0].c);
  if (allDebts[0].c > 0 && debts[0].c === 0) await gamification.grantAchievement(req.userId, 'debt_free', 1);
  if (streak[0] && streak[0].longest_streak >= 7) await gamification.grantAchievement(req.userId, 'streak_7', streak[0].longest_streak);
  if (streak[0] && streak[0].longest_streak >= 30) await gamification.grantAchievement(req.userId, 'streak_30', streak[0].longest_streak);
  res.json({ message: 'Conquistas recalculadas.' });
}));

router.get('/leaderboard/:familyId', asyncHandler(async (req, res) => {
  const familyId = req.params.familyId;
  const membership = await scope.roleInFamily(req.userId, familyId);
  if (!membership) throw Object.assign(new Error('Você não pertence a esta família.'), { status: 403 });
  const [rows] = await db.query(
    `SELECT u.id, u.name, u.photo_url, COALESCE(us.current_streak, 0) AS current_streak,
            COALESCE(us.longest_streak, 0) AS longest_streak, COALESCE(us.total_points, 0) AS total_points
     FROM family_members fm
     JOIN users u ON u.id = fm.user_id
     LEFT JOIN user_streaks us ON us.user_id = u.id
     WHERE fm.family_id = ?
     ORDER BY total_points DESC, current_streak DESC`,
    [familyId]
  );
  res.json({ ranking: rows });
}));

module.exports = router;
