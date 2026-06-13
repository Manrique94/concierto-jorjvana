const nodemailer = require('nodemailer');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Método no permitido' });
    return;
  }

  const { nombre, correo, codigos, pdfBase64 } = req.body || {};

  if (!correo || !pdfBase64) {
    res.status(400).json({ error: 'Faltan datos (correo o PDF).' });
    return;
  }

  if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
    res.status(500).json({ error: 'El envío de correos no está configurado en el servidor.' });
    return;
  }

  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: process.env.GMAIL_USER,
      pass: process.env.GMAIL_APP_PASSWORD,
    },
  });

  const codes = (codigos || []).join(', ');
  const archivo = `entradas_${String(nombre || 'JORJVANA').replace(/\s+/g, '_')}.pdf`;

  try {
    await transporter.sendMail({
      from: `JORJVANA <${process.env.GMAIL_USER}>`,
      to: correo,
      subject: 'Tus entradas - Concierto JORJVANA',
      text: `Hola ${nombre || ''},\n\nTus entradas para el Concierto Acústico JORJVANA están confirmadas.\nFecha: 17 de Julio 2026, 7:00 PM\nLugar: C.C. Vida Abundante\n\nCódigos: ${codes}\n\nAdjuntamos tu PDF con los códigos QR. ¡Te esperamos!`,
      attachments: [
        {
          filename: archivo,
          content: pdfBase64,
          encoding: 'base64',
        },
      ],
    });
    res.status(200).json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
