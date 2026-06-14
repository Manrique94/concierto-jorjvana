const nodemailer = require('nodemailer');
const QRCode = require('qrcode');

const EVENTO_DEFAULT = { fecha: '17 de Julio 2026', hora: '7:00 PM', lugar: 'C.C. Vida Abundante' };

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Método no permitido' });
    return;
  }

  const { nombre, correo, codigos, codigoPago, urlConsulta, evento } = req.body || {};

  if (!correo || !Array.isArray(codigos) || codigos.length === 0) {
    res.status(400).json({ error: 'Faltan datos (correo o códigos de entradas).' });
    return;
  }

  if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
    res.status(500).json({ error: 'El envío de correos no está configurado en el servidor.' });
    return;
  }

  const ev = { ...EVENTO_DEFAULT, ...(evento || {}) };

  try {
    const qrAttachments = await Promise.all(codigos.map(async (codigo, i) => ({
      filename: `qr_${i}.png`,
      content: await QRCode.toBuffer(String(codigo), { width: 200, margin: 1 }),
      cid: `qr${i}`,
    })));

    const filasEntradas = codigos.map((codigo, i) => `
      <tr>
        <td style="padding:8px;text-align:center"><img src="cid:qr${i}" width="120" height="120" alt="QR ${codigo}"></td>
        <td style="padding:8px;font-family:monospace;font-size:16px;font-weight:bold">${codigo}</td>
      </tr>`).join('');

    const enlaceConsulta = urlConsulta
      ? `<p><a href="${urlConsulta}">Consultar mis entradas</a></p>`
      : '';

    const html = `
      <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto">
        <h2>🎫 Tus entradas - Concierto JORJVANA</h2>
        <p>Hola ${nombre || ''},</p>
        <p>Tus entradas para el <b>Concierto Acústico JORJVANA</b> están confirmadas.</p>
        <p>📅 ${ev.fecha} &nbsp;·&nbsp; 🕖 ${ev.hora} &nbsp;·&nbsp; 📍 ${ev.lugar}</p>
        ${codigoPago ? `<p>Código de pago: <b>${codigoPago}</b></p>` : ''}
        <table style="width:100%;border-collapse:collapse">${filasEntradas}</table>
        <p>Presenta cada código QR (uno por entrada) en el ingreso.</p>
        ${enlaceConsulta}
        <p>¡Te esperamos!</p>
      </div>`;

    const codes = codigos.join(', ');
    const text = `Hola ${nombre || ''},\n\nTus entradas para el Concierto Acústico JORJVANA están confirmadas.\nFecha: ${ev.fecha}, ${ev.hora}\nLugar: ${ev.lugar}\n${codigoPago ? `Código de pago: ${codigoPago}\n` : ''}\nCódigos: ${codes}\n${urlConsulta ? `\nConsultar mis entradas: ${urlConsulta}\n` : ''}\n¡Te esperamos!`;

    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: process.env.GMAIL_USER,
        pass: process.env.GMAIL_APP_PASSWORD,
      },
    });

    await transporter.sendMail({
      from: `JORJVANA <${process.env.GMAIL_USER}>`,
      to: correo,
      subject: 'Tus entradas - Concierto JORJVANA',
      text,
      html,
      attachments: qrAttachments,
    });
    res.status(200).json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
