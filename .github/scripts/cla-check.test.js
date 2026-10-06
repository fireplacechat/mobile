'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { PHRASE, agrees, evaluate, run } = require('./cla-check.js');

const user = (login, type = 'User') => ({ login, type });
function fakeGithub({ comments = {}, commits = {}, prs = [] }) {
  const calls = { statuses: [], created: [] };
  const rest = {
    issues: { listComments: 'LC', createComment: async (a) => { calls.created.push(a); } },
    pulls: { listCommits: 'LCm', list: 'PL' },
    repos: { createCommitStatus: async (a) => { calls.statuses.push(a); } },
  };
  return {
    calls, rest,
    paginate: async (fn, p) => fn === 'LC' ? (comments[p.issue_number] || []) : fn === 'LCm' ? (commits[p.pull_number] || []) : prs,
  };
}
const ctx = (extra = {}) => ({ repo: { owner: 'o', repo: 'r' }, eventName: 'pull_request_target', payload: {}, ...extra });
const core = () => ({ messages: [], info(m) { this.messages.push(m); }, setFailed(m) { this.failed = m; } });

test('only the exact first line counts as agreement', () => {
  assert.ok(agrees(PHRASE));
  assert.ok(agrees(PHRASE + '\nOrganisation: Example Ltd'));
  assert.ok(!agrees('I agree'));
  assert.ok(!agrees('> ' + PHRASE));
  assert.ok(!agrees('no ' + PHRASE));
  assert.ok(!agrees(null));
});

test('unsigned author fails, signed author passes, case-insensitive', async () => {
  const pr = { number: 5, user: user('Alice'), head: { sha: 'abc' } };
  const github = fakeGithub({ commits: { 5: [{ author: user('Alice') }] } });
  let r = await evaluate({ github, owner: 'o', repo: 'r', pr, signed: new Set(), allow: new Set() });
  assert.deepEqual(r, { ok: false, missing: ['Alice'], unmapped: 0 });
  r = await evaluate({ github, owner: 'o', repo: 'r', pr, signed: new Set(['alice']), allow: new Set() });
  assert.equal(r.ok, true);
});

test('bots and allowlisted maintainers are exempt', async () => {
  const pr = { number: 6, user: user('dependabot[bot]', 'Bot'), head: { sha: 'x' } };
  const github = fakeGithub({ commits: { 6: [{ author: user('Maint') }] } });
  const r = await evaluate({ github, owner: 'o', repo: 'r', pr, signed: new Set(), allow: new Set(['maint']) });
  assert.equal(r.ok, true);
});

test('a second contributor on the same pull request must also have signed', async () => {
  const pr = { number: 7, user: user('Alice'), head: { sha: 'x' } };
  const github = fakeGithub({ commits: { 7: [{ author: user('Alice') }, { author: user('Bob') }] } });
  const r = await evaluate({ github, owner: 'o', repo: 'r', pr, signed: new Set(['alice']), allow: new Set() });
  assert.deepEqual(r.missing, ['Bob']);
});

test('a commit not linked to a GitHub account fails', async () => {
  const pr = { number: 8, user: user('Alice'), head: { sha: 'x' } };
  const github = fakeGithub({ commits: { 8: [{ author: null }] } });
  const r = await evaluate({ github, owner: 'o', repo: 'r', pr, signed: new Set(['alice']), allow: new Set() });
  assert.deepEqual(r, { ok: false, missing: [], unmapped: 1 });
});

test('run: pull request without signature gets a failing status and one comment', async () => {
  const pr = { number: 9, user: user('Carol'), head: { sha: 'sha9' } };
  const github = fakeGithub({ commits: { 9: [{ author: user('Carol') }] } });
  const c = core();
  await run({ github, context: ctx({ payload: { pull_request: pr } }), core: c }, { CLA_ISSUE: '3', CLA_ALLOWLIST: '' });
  assert.equal(github.calls.statuses[0].state, 'failure');
  assert.equal(github.calls.statuses[0].context, 'cla');
  assert.equal(github.calls.created.length, 1);
  assert.match(github.calls.created[0].body, /I have read the Fireplace Contributor License Agreement/);
});

test('run: signature comment on the issue turns the status green and no comment is added', async () => {
  const pr = { number: 10, user: user('Dana'), head: { sha: 'sha10' } };
  const github = fakeGithub({
    comments: { 3: [{ user: user('Dana'), body: PHRASE }] },
    commits: { 10: [{ author: user('Dana') }] }, prs: [pr],
  });
  const c = core();
  await run({ github, context: ctx({ eventName: 'issue_comment' }), core: c }, { CLA_ISSUE: '3', CLA_ALLOWLIST: '' });
  assert.equal(github.calls.statuses[0].state, 'success');
  assert.equal(github.calls.created.length, 0);
});

test('run: a bot account cannot sign on behalf of someone', async () => {
  const pr = { number: 11, user: user('Eve'), head: { sha: 's' } };
  const github = fakeGithub({ comments: { 3: [{ user: user('Eve', 'Bot'), body: PHRASE }] }, commits: { 11: [{ author: user('Eve') }] } });
  await run({ github, context: ctx({ payload: { pull_request: pr } }), core: core() }, { CLA_ISSUE: '3', CLA_ALLOWLIST: '' });
  assert.equal(github.calls.statuses[0].state, 'failure');
});

test('run: missing CLA_ISSUE fails loudly instead of passing everyone', async () => {
  const github = fakeGithub({});
  const c = core();
  await run({ github, context: ctx({ payload: { pull_request: { number: 1, user: user('x'), head: { sha: 's' } } } }), core: c }, {});
  assert.ok(c.failed);
  assert.equal(github.calls.statuses.length, 0);
});
