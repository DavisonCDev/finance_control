// Gamificação: streaks de uso e conquistas (spec §43).
//
// Nenhuma função aqui propaga erro: gamificação é acessória e não pode derrubar
// o cadastro de um lançamento.
const db = require('../db');
const dates = require('./dates');

/**
 * Registra atividade do usuário na data informada e atualiza o streak.
 * - last_entry_date = ontem  → streak + 1
 * - last_entry_date = hoje   → mantém (idempotente no mesmo dia)
 * - qualquer outro caso      → reinicia em 1
 */
async function registerActivity(userId, date = null) {
  try {
    const today = date ? dates.toIsoDate(dates.parseDate(date)) : dates.toIsoDate(new Date());

    const [rows] = await db.query('SELECT * FROM user_streaks WHERE user_id = ?', [userId]);

    if (rows.length === 0) {
      await db.query(
        `INSERT INTO user_streaks (user_id, current_streak, longest_streak, last_entry_date)
         VALUES (?, 1, 1, ?)`,
        [userId, today]
      );
      return { current_streak: 1, longest_streak: 1, last_entry_date: today };
    }

    const streak = rows[0];
    const last = streak.last_entry_date ? String(streak.last_entry_date).slice(0, 10) : null;

    // Já registrou hoje: nada muda.
    if (last === today) return streak;

    const yesterday = dates.toIsoDate(dates.addDays(today, -1));
    const current = last === yesterday ? Number(streak.current_streak || 0) + 1 : 1;
    const longest = Math.max(Number(streak.longest_streak || 0), current);

    await db.query(
      'UPDATE user_streaks SET current_streak = ?, longest_streak = ?, last_entry_date = ? WHERE user_id = ?',
      [current, longest, today, userId]
    );

    return { ...streak, current_streak: current, longest_streak: longest, last_entry_date: today };
  } catch (err) {
    console.error('registerActivity:', err.message);
    return null;
  }
}

/**
 * Upsert de progresso em uma conquista. Quando o progresso alcança o target,
 * marca earned_at e credita os pontos em user_streaks.total_points (uma vez só).
 */
async function grantAchievement(userId, code, progress = 1) {
  try {
    const [achievements] = await db.query('SELECT * FROM achievements WHERE code = ?', [code]);
    if (achievements.length === 0) return null;

    const achievement = achievements[0];
    const target = Number(achievement.target || 1);

    const [existing] = await db.query(
      'SELECT * FROM user_achievements WHERE user_id = ? AND achievement_code = ?',
      [userId, code]
    );

    // Conquista já premiada: não reprocessa pontos.
    if (existing.length > 0 && existing[0].earned_at) return existing[0];

    const newProgress = Math.max(Number(progress || 0), existing.length > 0 ? Number(existing[0].progress || 0) : 0);
    const earned = newProgress >= target;

    await db.query(
      `INSERT INTO user_achievements (user_id, achievement_code, progress, earned_at)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE progress = VALUES(progress), earned_at = VALUES(earned_at)`,
      [userId, code, newProgress, earned ? new Date() : null]
    );

    if (earned) {
      await db.query(
        `INSERT INTO user_streaks (user_id, total_points) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE total_points = total_points + VALUES(total_points)`,
        [userId, Number(achievement.points || 0)]
      );
    }

    const [rows] = await db.query(
      'SELECT * FROM user_achievements WHERE user_id = ? AND achievement_code = ?',
      [userId, code]
    );
    return rows[0] || null;
  } catch (err) {
    console.error('grantAchievement:', err.message);
    return null;
  }
}

/**
 * Conquistas disparadas pelo simples ato de lançar: primeiro lançamento e
 * marcos de sequência (7 e 30 dias).
 */
async function checkTransactionAchievements(userId) {
  try {
    const [counts] = await db.query(
      'SELECT COUNT(*) AS total FROM transactions WHERE user_id = ? AND deleted_at IS NULL',
      [userId]
    );
    if (Number(counts[0]?.total || 0) >= 1) await grantAchievement(userId, 'first_transaction', 1);

    const [streaks] = await db.query('SELECT current_streak FROM user_streaks WHERE user_id = ?', [userId]);
    const current = Number(streaks[0]?.current_streak || 0);
    if (current > 0) {
      await grantAchievement(userId, 'streak_7', Math.min(current, 7));
      await grantAchievement(userId, 'streak_30', Math.min(current, 30));
    }
  } catch (err) {
    console.error('checkTransactionAchievements:', err.message);
  }
}

module.exports = { registerActivity, grantAchievement, checkTransactionAchievements };
