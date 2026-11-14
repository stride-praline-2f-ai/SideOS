'use strict';
const fs = require('node:fs');
function ensure(value, message) { if (!value) throw new Error(message); }
function validateBranches(branches, expected, runningSHA) {
  ensure(expected && typeof expected === 'object', 'Missing branch snapshot');
  for (const branch of branches) {
    const wanted = branch.name === 'release/maintenance' ? runningSHA : expected[branch.name];
    ensure(wanted && branch.commit.sha === wanted, 'A branch changed or is unrecognized; preserve concurrent work');
  }
  ensure(branches.length === Object.keys(expected).length, 'Branch inventory changed');
}
module.exports = async function maintain({github, context, core}) {
  ensure(context.ref === 'refs/heads/release/maintenance', 'Wrong maintenance branch');
  const api = {...context.repo};
  const request = JSON.parse(fs.readFileSync('.github/maintenance-request.json', 'utf8'));
  if (request.operation === 'idle') { core.info('No maintenance requested.'); return; }
  if (request.operation === 'replace-source') {
    for (const key of ['expected_main', 'source']) ensure(/^[a-f0-9]{40}$/.test(request[key]), 'Invalid source identity');
    const main = (await github.rest.git.getRef({...api, ref: 'heads/main'})).data;
    ensure(main.object.sha === request.expected_main, 'Main changed; do not overwrite concurrent work');
    const branches = await github.paginate(github.rest.repos.listBranches, {...api, per_page: 100});
    validateBranches(branches, request.expected_refs, context.sha);
    for (const branch of branches) {
      ensure(['main', 'ipa/device', 'release/publish', 'release/maintenance'].includes(branch.name) || request.retire_branches?.includes(branch.name), 'Unexpected branch; preserve it for review');
    }
    const source = (await github.rest.git.getCommit({...api, commit_sha: request.source})).data;
    const commit = (await github.rest.git.createCommit({...api, message: 'SideOS release source', tree: source.tree.sha, parents: [],
      author: {name: 'SideOS contributors', email: 'noreply@users.noreply.github.com'},
      committer: {name: 'SideOS contributors', email: 'noreply@users.noreply.github.com'}})).data;
    const still = (await github.rest.git.getRef({...api, ref: 'heads/main'})).data;
    ensure(still.object.sha === request.expected_main, 'Main changed during preparation');
    await github.rest.git.updateRef({...api, ref: 'heads/main', sha: commit.sha, force: true});
    for (const branch of branches) {
      if (branch.name === 'main' || branch.name === 'ipa/device') continue;
      if (['release/publish', 'release/maintenance'].includes(branch.name)) {
        await github.rest.git.updateRef({...api, ref: `heads/${branch.name}`, sha: commit.sha, force: true});
      } else {
        ensure(request.retire_branches?.includes(branch.name), 'Unexpected branch; preserve it for review');
        await github.rest.git.deleteRef({...api, ref: `heads/${branch.name}`});
      }
    }
    core.info(`Replacement source ready: ${commit.sha}`);
    core.setOutput('source_sha', commit.sha);
    await core.summary.addHeading('Replacement release source').addRaw(commit.sha).write();
    return;
  }
  if (request.operation === 'withdraw') {
    ensure(Number.isSafeInteger(request.release_id) && /^[a-f0-9]{40}$/.test(request.source), 'Invalid release identity');
    ensure(/^v\d+\.\d+\.\d+-build\.\d+$/.test(request.tag), 'Invalid release tag');
    const release = (await github.rest.repos.getRelease({...api, release_id: request.release_id})).data;
    ensure(release.tag_name === request.tag && release.target_commitish === request.source, 'Release identity changed');
    await github.rest.repos.updateRelease({...api, release_id: release.id, draft: true});
    try {
      const tagged = (await github.rest.repos.getCommit({...api, ref: request.tag})).data;
      ensure(tagged.sha === request.source, 'Tag identity changed');
      await github.rest.git.deleteRef({...api, ref: `tags/${request.tag}`});
    } catch (error) { if (error.status !== 404 && error.status !== 422) throw error; }
    core.info('Superseded release withdrawn. A replacement will be published after verification.');
    return;
  }
  throw new Error('Unsupported maintenance operation');
};
module.exports.validateBranches = validateBranches;
