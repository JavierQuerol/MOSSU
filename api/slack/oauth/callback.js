import fetch from 'node-fetch';

export default async function handler(req, res) {
  const { code } = req.query;
  if (!code) return res.status(400).send("Falta el parámetro 'code'");

  const params = new URLSearchParams({
    code,
    client_id: process.env.SLACK_CLIENT_ID,
    client_secret: process.env.SLACK_CLIENT_SECRET,
    redirect_uri: process.env.SLACK_REDIRECT_URI
  });

  const slackRes = await fetch(
    "https://slack.com/api/oauth.v2.access",
    { method: "POST", headers: {"Content-Type":"application/x-www-form-urlencoded"}, body: params }
  );
  const data = await slackRes.json();

  if (!data.ok) return res.status(400).send(`Error Slack: ${data.error}`);

  const accessToken = data.authed_user?.access_token;
  const slackUserId = data.authed_user?.id;
  const baseUrl = process.env.FRONTEND_URL;
  const url = `${baseUrl}/redirect.html?token=${encodeURIComponent(accessToken)}&user=${encodeURIComponent(slackUserId)}`;

  return res.redirect(url);
}
