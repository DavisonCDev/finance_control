// Envio de e-mails transacionais (verificação de conta e recuperação de senha).
const nodemailer = require('nodemailer');

const APP_URL = process.env.APP_URL || 'http://localhost:3000';
const FROM = process.env.MAIL_FROM || 'Finance Control <nao-responda@finance-control.local>';

let transport;

// Sem SMTP configurado o fluxo precisa continuar funcionando em desenvolvimento,
// então caímos num transporte que só imprime a mensagem no console.
function consoleTransport() {
  return {
    sendMail: async (message) => {
      console.log('[mailer] SMTP não configurado — e-mail apenas registrado no console:');
      console.log(`  para: ${message.to}`);
      console.log(`  assunto: ${message.subject}`);
      if (message.text) console.log(`  conteúdo: ${message.text}`);
      return { messageId: 'console', accepted: [message.to] };
    },
  };
}

function getTransport() {
  if (transport) return transport;

  if (!process.env.SMTP_HOST) {
    transport = consoleTransport();
    return transport;
  }

  transport = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: String(process.env.SMTP_SECURE || 'false') === 'true',
    auth: process.env.SMTP_USER
      ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
      : undefined,
  });
  return transport;
}

/**
 * Envia um e-mail. Nunca lança: falhas de SMTP não devem derrubar cadastro,
 * recuperação de senha ou qualquer outro fluxo de negócio.
 */
async function sendMail({ to, subject, text, html }) {
  if (!to) return false;
  try {
    await getTransport().sendMail({ from: FROM, to, subject, text, html });
    return true;
  } catch (err) {
    console.error('mailer:', err.message);
    return false;
  }
}

function layout(title, body, actionUrl, actionLabel) {
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222">
  <h2>${title}</h2>
  ${body}
  <p><a href="${actionUrl}" style="display:inline-block;padding:10px 18px;background:#1565C0;color:#fff;text-decoration:none;border-radius:6px">${actionLabel}</a></p>
  <p style="font-size:13px;color:#666">Se o botão não funcionar, copie e cole este endereço no navegador:<br>${actionUrl}</p>
</div>`;
}

async function sendVerificationEmail(user, token) {
  const url = `${APP_URL}/auth/verify-email?token=${encodeURIComponent(token)}`;
  return sendMail({
    to: user.email,
    subject: 'Confirme seu e-mail — Finance Control',
    text: `Olá, ${user.name || ''}!\n\nConfirme seu e-mail acessando o link abaixo:\n${url}\n\nSe não foi você que criou a conta, ignore esta mensagem.`,
    html: layout(
      'Confirme seu e-mail',
      `<p>Olá, ${user.name || ''}! Falta pouco para ativar sua conta no Finance Control.</p>`,
      url,
      'Confirmar e-mail'
    ),
  });
}

async function sendPasswordResetEmail(user, token) {
  const url = `${APP_URL}/auth/reset-password?token=${encodeURIComponent(token)}`;
  return sendMail({
    to: user.email,
    subject: 'Redefinição de senha — Finance Control',
    text: `Olá, ${user.name || ''}!\n\nUse o link abaixo para definir uma nova senha (válido por 1 hora):\n${url}\n\nSe não foi você que solicitou, ignore esta mensagem.`,
    html: layout(
      'Redefinição de senha',
      `<p>Olá, ${user.name || ''}! Recebemos um pedido para redefinir sua senha. O link é válido por 1 hora.</p>`,
      url,
      'Redefinir senha'
    ),
  });
}

module.exports = { sendMail, sendVerificationEmail, sendPasswordResetEmail, APP_URL };
