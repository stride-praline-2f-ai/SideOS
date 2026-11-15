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
module.exports = async function maintain({github, context, core, request: supplied}) {
  const api = {...context.repo};
  const request = supplied || JSON.parse(fs.readFileSync('.github/maintenance-request.json', 'utf8'));
  ensure(context.ref === 'refs/heads/release/maintenance' || request.operation === 'retire-superseded-builds' && context.ref === 'refs/heads/release/publish', 'Wrong maintenance branch');
  if (request.operation === 'idle') { core.info('No maintenance requested.'); return; }
  if (request.operation === 'commit-reviewed-update') {
    for (const name of ['expected_main', 'tree']) ensure(/^[a-f0-9]{40}$/.test(request[name]), 'Invalid metadata identity');
    const head = (await github.rest.git.getRef({...api, ref: 'heads/main'})).data;
    ensure(head.object.sha === request.expected_main, 'Main changed; preserve concurrent work');
    const commit = (await github.rest.git.createCommit({...api, message: 'Update SideOS release source', tree: request.tree, parents: [request.expected_main],
      author: {name: 'SideOS contributors', email: 'noreply@users.noreply.github.com'},
      committer: {name: 'SideOS contributors', email: 'noreply@users.noreply.github.com'}})).data;
    const diff = (await github.request('GET /repos/{owner}/{repo}/compare/{basehead}', {...api, basehead: `${request.expected_main}...${commit.sha}`})).data;
    ensure(diff.files?.length > 0 && diff.files.length <= 20 && diff.files.every(file => request.allowed_paths?.includes(file.filename)), 'Metadata update changes unexpected files');
    const still = (await github.rest.git.getRef({...api, ref: 'heads/main'})).data;
    ensure(still.object.sha === request.expected_main, 'Main changed during metadata preparation');
    await github.rest.git.updateRef({...api, ref: 'heads/main', sha: commit.sha, force: false});
    await github.rest.git.updateRef({...api, ref: 'heads/release/maintenance', sha: commit.sha, force: true});
    core.info(`Release metadata ready: ${commit.sha}`); core.setOutput('metadata_sha', commit.sha);
    return;
  }
  if (request.operation === 'retire-superseded-builds') {
    ensure(Number.isSafeInteger(request.keep_run_id) && Number.isSafeInteger(request.replacement_release_id), 'Invalid replacement identity');
    ensure(/^[a-f0-9]{40}$/.test(request.source) && /^[a-f0-9]{64}$/.test(request.ipa_sha256), 'Invalid replacement source/checksum');
    const replacement = (await github.rest.repos.getRelease({...api, release_id: request.replacement_release_id})).data;
    ensure(!replacement.draft && replacement.target_commitish === request.source, 'Replacement must already be public and source-matching');
    const assets = await github.paginate(github.rest.repos.listReleaseAssets, {...api, release_id: replacement.id, per_page: 100});
    ensure(assets.some(asset => asset.name.endsWith('-unsigned.ipa') && asset.digest === `sha256:${request.ipa_sha256}`), 'Replacement IPA checksum is not verified');
    const keep = (await github.rest.actions.getWorkflowRun({...api, run_id: request.keep_run_id})).data;
    ensure(keep.conclusion === 'success' && keep.head_sha === request.source && keep.path === '.github/workflows/private-build.yml', 'Replacement device workflow must succeed');
    const publication = (await github.rest.actions.getWorkflowRun({...api, run_id: context.runId})).data;
    ensure(Number.isFinite(Date.parse(publication.created_at)) && Number.isFinite(Date.parse(keep.created_at)), 'Missing publication/build timestamp');
    const retiredReleases = [];
    for (const id of request.retire_release_ids || []) {
      ensure(Number.isSafeInteger(id) && id !== replacement.id, 'Invalid superseded release');
      let old;
      try { old = (await github.rest.repos.getRelease({...api, release_id: id})).data; }
      catch (error) { if (error.status === 404) continue; throw error; }
      ensure(old.draft && old.target_commitish !== request.source, 'Only previously withdrawn superseded releases may be retired');
      retiredReleases.push(id);
    }
    const artifacts = await github.paginate(github.rest.actions.listArtifactsForRepo, {...api, per_page: 100});
    let removed = 0;
    for (const artifact of artifacts) {
      if (artifact.name !== 'SideOS3-Device-IPA' || artifact.workflow_run?.id === request.keep_run_id || artifact.created_at >= keep.created_at) continue;
      await github.rest.actions.deleteArtifact({...api, artifact_id: artifact.id}); removed += 1;
    }
    for (const id of retiredReleases) {
      await github.rest.repos.deleteRelease({...api, release_id: id});
    }
    const runs = await github.paginate(github.rest.actions.listWorkflowRunsForRepo, {...api, status: 'completed', per_page: 100});
    for (const run of runs) {
      if (run.id === request.keep_run_id || run.head_sha === request.source || run.head_sha === context.sha || run.created_at >= publication.created_at) continue;
      if (run.head_repository?.full_name !== `${api.owner}/${api.repo}`) continue;
      await github.rest.actions.deleteWorkflowRun({...api, run_id: run.id});
    }
    const caches = (await github.request('GET /repos/{owner}/{repo}/actions/caches', {...api, per_page: 100})).data.actions_caches;
    for (const cache of caches || []) {
      if (!/^(sideos3-|tahoe-)/.test(cache.key) || cache.created_at >= keep.created_at) continue;
      await github.request('DELETE /repos/{owner}/{repo}/actions/caches/{cache_id}', {...api, cache_id: cache.id});
    }
    core.info(`Replacement verified. Removed ${removed} superseded IPA artifacts and retired the withdrawn release.`);
    return;
  }
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
