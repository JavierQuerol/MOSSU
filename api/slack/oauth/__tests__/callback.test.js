import test from 'node:test';
import assert from 'assert/strict';

function createRes() {
  return {
    statusCode: 200,
    body: undefined,
    redirectedTo: undefined,
    status(code) { this.statusCode = code; return this; },
    send(body) { this.body = body; return this; },
    redirect(url) { this.redirectedTo = url; return this; }
  };
}

// set dummy env vars used by the handler
process.env.SLACK_CLIENT_ID = 'id';
process.env.SLACK_CLIENT_SECRET = 'secret';
process.env.SLACK_REDIRECT_URI = 'https://example.com/callback';
process.env.FRONTEND_URL = 'https://mossu.example.com';

test('returns 400 when code param is missing', async (t) => {
  const { default: handler } = await import('../callback.js');
  const res = createRes();
  await handler({ query: {} }, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body, "Falta el parámetro 'code'");
});

test('redirects to app when Slack auth succeeds', async (t) => {
  const mock = t.mock.module('node-fetch', {
    defaultExport: async () => ({
      json: async () => ({ ok: true, authed_user: { access_token: 'tok', id: 'U1' } })
    })
  });
  const { default: handler } = await import('../callback.js?success');
  const res = createRes();
  await handler({ query: { code: '123' } }, res);
  mock.restore();
  assert.equal(res.redirectedTo, `${process.env.FRONTEND_URL}/redirect.html?token=tok&user=U1`);
});

test('returns Slack error message', async (t) => {
  const mock = t.mock.module('node-fetch', {
    defaultExport: async () => ({
      json: async () => ({ ok: false, error: 'invalid_code' })
    })
  });
  const { default: handler } = await import('../callback.js?error');
  const res = createRes();
  await handler({ query: { code: 'bad' } }, res);
  mock.restore();
  assert.equal(res.statusCode, 400);
  assert.equal(res.body, 'Error Slack: invalid_code');
});
