'use strict';
const assert = require('node:assert/strict');
const {validateBranches} = require('./release-maintenance.cjs');
const expected = {main: 'a'.repeat(40), 'release/maintenance': 'b'.repeat(40)};
const running = 'c'.repeat(40);
const branches = [{name: 'main', commit: {sha: expected.main}}, {name: 'release/maintenance', commit: {sha: running}}];
validateBranches(branches, expected, running);
assert.throws(() => validateBranches([{...branches[0], commit: {sha: 'd'.repeat(40)}}, branches[1]], expected, running));
assert.throws(() => validateBranches([...branches, {name: 'concurrent-work', commit: {sha: 'e'.repeat(40)}}], expected, running));
assert.throws(() => validateBranches(branches.slice(0, 1), expected, running));
console.log('Source replacement refuses changed, missing and unrecognized branches before rewriting a ref.');

async function retirementFixture(change = {}) {
  const maintain = require('./release-maintenance.cjs');
  const mutations = [];
  const source = 'a'.repeat(40), metadata = 'c'.repeat(40), digest = 'd'.repeat(64);
  const before = '2026-11-14T20:00:00Z', buildTime = '2026-11-15T00:00:00Z', publishTime = '2026-11-15T01:00:00Z', after = '2026-11-15T02:00:00Z';
  const keep = {id: 200, conclusion: 'success', head_sha: source, path: '.github/workflows/private-build.yml', created_at: buildTime};
  const repos = {
    async getRelease({release_id}) { return {data: release_id === 2 ? {id: 2, draft: false, target_commitish: source, ...change.release} : {id: 1, draft: true, target_commitish: 'b'.repeat(40), ...change.oldRelease}}; },
    listReleaseAssets() {},
    async deleteRelease({release_id}) { mutations.push(['release', release_id]); }
  };
  const actions = {
    async getWorkflowRun({run_id}) { return {data: run_id === 200 ? {...keep, ...change.build} : {id: 300, created_at: publishTime}}; },
    listArtifactsForRepo() {}, listWorkflowRunsForRepo() {},
    async deleteArtifact({artifact_id}) { mutations.push(['artifact', artifact_id]); },
    async deleteWorkflowRun({run_id}) { mutations.push(['run', run_id]); }
  };
  const github = {rest: {repos, actions}, async paginate(method) {
    if (method === repos.listReleaseAssets) return [{name: 'SideOS-Build-15-unsigned.ipa', digest: `sha256:${digest}`, ...change.asset}];
    if (method === actions.listArtifactsForRepo) return [
      {id: 10, name: 'SideOS3-Device-IPA', workflow_run: {id: 100}, created_at: before},
      {id: 20, name: 'SideOS3-Device-IPA', workflow_run: {id: 200}, created_at: buildTime},
      {id: 30, name: 'SideOS3-Device-IPA', workflow_run: {id: 210}, created_at: after}];
    if (method === actions.listWorkflowRunsForRepo) return [
      {id: 100, head_sha: 'b'.repeat(40), created_at: before, head_repository: {full_name: 'example/SideOS'}},
      {id: 200, head_sha: source, created_at: buildTime, head_repository: {full_name: 'example/SideOS'}},
      {id: 210, head_sha: 'e'.repeat(40), created_at: after, head_repository: {full_name: 'example/SideOS'}},
      {id: 220, head_sha: metadata, created_at: before, head_repository: {full_name: 'example/SideOS'}}];
    throw Error('Unexpected pagination');
  }, async request(route, args) {
    if (route.startsWith('GET ')) return {data: {actions_caches: [{id: 11, key: 'sideos3-host-old', created_at: before}, {id: 12, key: 'sideos3-host-current', created_at: after}, {id: 13, key: 'unrelated-cache', created_at: before}]}};
    mutations.push(['cache', args.cache_id]); return {data: {}};
  }};
  try {
    await maintain({github, context: {ref: 'refs/heads/release/publish', repo: {owner: 'example', repo: 'SideOS'}, sha: metadata, runId: 300}, core: {info() {}},
      request: {operation: 'retire-superseded-builds', replacement_release_id: 2, keep_run_id: 200, source, ipa_sha256: digest, retire_release_ids: [1]}});
    return {mutations};
  } catch (error) { return {mutations, error}; }
}
(async () => {
  const successful = await retirementFixture();
  assert.equal(successful.error, undefined);
  assert.deepEqual(successful.mutations, [['artifact', 10], ['release', 1], ['run', 100], ['cache', 11]]);
  for (const change of [{release: {draft: true}}, {asset: {digest: 'sha256:wrong'}}, {build: {conclusion: 'failure'}}, {oldRelease: {draft: false}}]) {
    const refused = await retirementFixture(change);
    assert.ok(refused.error); assert.deepEqual(refused.mutations, []);
  }
  console.log('Retirement requires a verified public replacement; failed, mismatched and public-old-release cases make zero deletion. Current/future builds and caches survive.');
})().catch(error => { console.error(error); process.exitCode = 1; });
