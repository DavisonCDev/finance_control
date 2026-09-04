// Regras automáticas aplicadas a lançamentos (spec §34).
const db = require('../db');

function normalize(value) {
  return String(value ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

function matches(rule, transaction) {
  const field = rule.match_field;
  const target = field === 'amount' ? Number(transaction.amount)
    : field === 'account' ? transaction.account_id
    : field === 'card' ? transaction.card_id
    : field === 'type' ? transaction.type
    : field === 'category' ? transaction.category_id
    : transaction.description;

  if (field === 'amount') {
    const value = Number(rule.match_value);
    if (rule.match_operator === 'greater_than') return Number(target) > value;
    if (rule.match_operator === 'less_than') return Number(target) < value;
    return Number(target) === value;
  }

  if (['account', 'card', 'category'].includes(field)) {
    return String(target ?? '') === String(rule.match_value);
  }

  const haystack = normalize(target);
  const needle = normalize(rule.match_value);

  switch (rule.match_operator) {
    case 'equals': return haystack === needle;
    case 'contains': return haystack.includes(needle);
    case 'not_contains': return !haystack.includes(needle);
    case 'starts_with': return haystack.startsWith(needle);
    case 'ends_with': return haystack.endsWith(needle);
    case 'regex':
      try {
        return new RegExp(rule.match_value, 'i').test(String(target ?? ''));
      } catch {
        return false;
      }
    default: return false;
  }
}

/**
 * Aplica as regras ativas do usuário sobre um lançamento.
 * Retorna { transaction, tagIds, requiresConfirmation, appliedRuleIds }.
 * Não persiste nada: quem chama decide se salva.
 */
async function applyRules(userId, transaction) {
  const [rules] = await db.query(
    'SELECT * FROM auto_rules WHERE user_id = ? AND active = TRUE ORDER BY priority DESC, id ASC',
    [userId]
  );

  const result = { ...transaction };
  const tagIds = [];
  const appliedRuleIds = [];
  let requiresConfirmation = false;

  for (const rule of rules) {
    if (!matches(rule, result)) continue;
    appliedRuleIds.push(rule.id);

    switch (rule.action_type) {
      case 'set_category':
        result.category_id = Number(rule.action_value) || result.category_id;
        break;
      case 'add_tag':
        if (rule.action_value) tagIds.push(Number(rule.action_value));
        break;
      case 'set_account':
        result.account_id = Number(rule.action_value) || result.account_id;
        break;
      case 'set_card':
        result.card_id = Number(rule.action_value) || result.card_id;
        break;
      case 'set_description':
        result.description = rule.action_value || result.description;
        break;
      case 'mark_transfer':
        result.type = 'transfer';
        result.transfer_account_id = Number(rule.action_value) || result.transfer_account_id;
        break;
      case 'require_confirmation':
        requiresConfirmation = true;
        break;
      case 'link_invoice':
        result.link_invoice = true;
        break;
    }

    if (rule.stop_processing) break;
  }

  if (appliedRuleIds.length > 0) {
    await db.query(
      `UPDATE auto_rules SET times_applied = times_applied + 1 WHERE id IN (${appliedRuleIds.map(() => '?').join(',')})`,
      appliedRuleIds
    );
  }

  if (result.source === 'manual' && appliedRuleIds.length > 0) result.source = 'rule';

  return { transaction: result, tagIds, requiresConfirmation, appliedRuleIds };
}

module.exports = { applyRules, matches, normalize };
