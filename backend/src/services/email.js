import net from 'node:net';
import tls from 'node:tls';

const getConfig = () => ({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 465),
  user: process.env.SMTP_USER,
  pass: process.env.SMTP_PASS,
  from: process.env.SMTP_FROM || process.env.SMTP_USER,
  secure: String(process.env.SMTP_SECURE || 'true').toLowerCase() !== 'false'
});

const readResponse = (socket) =>
  new Promise((resolve, reject) => {
    let buffer = '';
    const onData = (data) => {
      buffer += data.toString();
      const lines = buffer.split(/\r?\n/).filter(Boolean);
      const last = lines[lines.length - 1];
      if (last && /^\d{3} /.test(last)) {
        socket.off('data', onData);
        resolve(last);
      }
    };
    const onError = (err) => {
      socket.off('data', onData);
      reject(err);
    };
    socket.on('data', onData);
    socket.once('error', onError);
  });

const sendLine = (socket, line) => {
  socket.write(`${line}\r\n`);
};

const expectOk = async (socket) => {
  const line = await readResponse(socket);
  const code = Number(line.slice(0, 3));
  if (code >= 400) throw new Error(`SMTP error: ${line}`);
  return line;
};

const authLogin = async (socket, user, pass) => {
  sendLine(socket, 'AUTH LOGIN');
  await expectOk(socket);
  sendLine(socket, Buffer.from(user).toString('base64'));
  await expectOk(socket);
  sendLine(socket, Buffer.from(pass).toString('base64'));
  await expectOk(socket);
};

const buildMessage = ({ from, to, subject, text }) => {
  const headers = [
    `From: ${from}`,
    `To: ${to.join(', ')}`,
    `Subject: ${subject}`,
    `Date: ${new Date().toUTCString()}`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset="UTF-8"'
  ];
  return `${headers.join('\r\n')}\r\n\r\n${text}`;
};

export const sendEmail = async ({ to, subject, text }) => {
  const config = getConfig();
  if (!config.host || !config.from) {
    throw new Error('SMTP_HOST and SMTP_FROM must be set to send email');
  }
  if (!Array.isArray(to) || to.length === 0) {
    throw new Error('Email recipients are required');
  }

  const socket = config.secure
    ? tls.connect({ host: config.host, port: config.port })
    : net.connect({ host: config.host, port: config.port });

  await expectOk(socket);
  sendLine(socket, `EHLO ${config.host}`);
  await expectOk(socket);

  if (config.user && config.pass) {
    await authLogin(socket, config.user, config.pass);
  }

  sendLine(socket, `MAIL FROM:<${config.from}>`);
  await expectOk(socket);

  for (const recipient of to) {
    sendLine(socket, `RCPT TO:<${recipient}>`);
    await expectOk(socket);
  }

  sendLine(socket, 'DATA');
  await expectOk(socket);

  const message = buildMessage({ from: config.from, to, subject, text });
  socket.write(`${message}\r\n.\r\n`);
  await expectOk(socket);

  sendLine(socket, 'QUIT');
  socket.end();
};
