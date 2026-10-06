'use strict';
// Checks that everyone who contributed to a pull request has agreed to the Fireplace
// Contributor License Agreement by commenting on the signatures issue, and reports the
// result as a commit status named `cla`. It only calls the GitHub API; it never runs
// code from the pull request.

const PHRASE =
  'I have read the Fireplace Contributor License Agreement and I agree to its terms.';
const CONTEXT = 'cla';
const MARKER = '<!-- fireplace-cla-check -->';

// The first line of the comment must be the agreement phrase; later lines may name an organisation.
function agrees(body) {
  return (body || '').split(/\r?\n/)[0].trim() === PHRASE;
}

async function signers({ github, owner, repo, issue }) {
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner, repo, issue_number: issue, per_page: 100,
  });
  const set = new Set();
  for (const c of comments) {
    if (c.user && c.user.type === 'User' && agrees(c.body)) set.add(c.user.login.toLowerCase());
  }
  return set;
}

function exempt(user, allow) {
  return !!user && (user.type === 'Bot' || allow.has(user.login.toLowerCase()));
}

// Returns { ok, missing: [logins], unmapped: number } for one pull request.
async function evaluate({ github, owner, repo, pr, signed, allow }) {
  const commits = await github.paginate(github.rest.pulls.listCommits, {
    owner, repo, pull_number: pr.number, per_page: 100,
  });
  const people = new Map(); // lowercase login -> user
  if (pr.user) people.set(pr.user.login.toLowerCase(), pr.user);
  let unmapped = 0;
  for (const c of commits) {
    if (c.author) people.set(c.author.login.toLowerCase(), c.author);
    else unmapped += 1; // commit email is not linked to a GitHub account
  }
  const missing = [];
  for (const [login, user] of people) {
    if (!exempt(user, allow) && !signed.has(login)) missing.push(user.login);
  }
  return { ok: missing.length === 0 && unmapped === 0, missing, unmapped };
}

async function report({ github, owner, repo, pr, result, claUrl, issueUrl }) {
  const state = result.ok ? 'success' : 'failure';
  const description = result.ok
    ? 'Everyone on this pull request has agreed to the CLA.'
    : result.missing.length
      ? `CLA agreement needed from: ${result.missing.join(', ')}`.slice(0, 140)
      : 'Some commits are not linked to a GitHub account.';
  await github.rest.repos.createCommitStatus({
    owner, repo, sha: pr.head.sha, state, context: CONTEXT, description,
    target_url: result.ok ? claUrl : issueUrl,
  });
  if (result.ok) return;
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner, repo, issue_number: pr.number, per_page: 100,
  });
  if (comments.some((c) => (c.body || '').includes(MARKER))) return; // ask only once
  const lines = [MARKER, 'Thank you for contributing to Fireplace.'];
  if (result.missing.length) {
    lines.push(
      '', `Before this can be merged, ${result.missing.map((m) => '@' + m).join(', ')} need(s) to agree to the ` +
      `[Contributor License Agreement](${claUrl}). You keep ownership of your work; the agreement lets the project keep distributing it.`,
      '', `Please post this exact comment on the [signatures issue](${issueUrl}):`,
      '', `> ${PHRASE}`, '', 'One comment covers all your future contributions. This check updates by itself.');
  }
  if (result.unmapped) {
    lines.push('', `${result.unmapped} commit(s) use an email address that is not linked to a GitHub account, so the author ` +
      'cannot be checked. Add the email to your GitHub account, or re-author the commits.');
  }
  await github.rest.issues.createComment({ owner, repo, issue_number: pr.number, body: lines.join('\n') });
}

async function run({ github, context, core }, env = process.env) {
  const { owner, repo } = context.repo;
  const issue = Number(env.CLA_ISSUE);
  if (!issue) { core.setFailed('CLA_ISSUE is not set: create the signatures issue and set the repository variable.'); return; }
  const allow = new Set((env.CLA_ALLOWLIST || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean));
  const base = `https://github.com/${owner}/${repo}`;
  const claUrl = `${base}/blob/main/.github/CLA.md`;
  const issueUrl = `${base}/issues/${issue}`;
  const signed = await signers({ github, owner, repo, issue });

  let prs;
  if (context.eventName === 'pull_request_target') prs = [context.payload.pull_request];
  else prs = await github.paginate(github.rest.pulls.list, { owner, repo, state: 'open', per_page: 100 });

  for (const pr of prs) {
    const result = await evaluate({ github, owner, repo, pr, signed, allow });
    core.info(`PR #${pr.number}: ${result.ok ? 'ok' : 'missing ' + result.missing.join(',') + (result.unmapped ? ` +${result.unmapped} unmapped` : '')}`);
    await report({ github, owner, repo, pr, result, claUrl, issueUrl });
  }
}

module.exports = { PHRASE, agrees, signers, exempt, evaluate, report, run };
