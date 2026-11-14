const assert = require('node:assert/strict');
const reuse = require('./reuse-device-ipa.cjs');
const sha = 'a'.repeat(40);
async function scenario(patch = {}, artifactPatch = {}, error = false) {
  const outputs = {};
  const run = {id: 1, head_sha: sha, conclusion: 'success', event: 'push', head_branch: 'ipa/device', head_repository: {full_name: 'owner/repo'}, ...patch};
  const artifact = {id: 2, name: 'SideOS3-Device-IPA', size_in_bytes: 1000, expired: false, workflow_run: {head_sha: sha}, ...artifactPatch};
  const core = {setOutput: (k, v) => outputs[k] = v, info() {}, summary: {addHeading() {return this;}, addLink() {return this;}, addRaw() {return this;}, async write() {}}};
  const github = {rest: {actions: {
    async listWorkflowRuns() {if (error) throw Error('offline'); return {data: {workflow_runs: [run]}};},
    async listWorkflowRunArtifacts() {return {data: {artifacts: [artifact]}};}
  }}};
  await reuse({github, core, context: {repo: {owner: 'owner', repo: 'repo'}, sha, runId: 9}});
  return outputs;
}
(async () => {
  assert.equal((await scenario()).reused, 'true');
  for (const patch of [{head_sha: 'b'.repeat(40)}, {conclusion: 'failure'}, {head_repository: {full_name: 'fork/repo'}}, {event: 'pull_request'}, {id: 9}])
    assert.equal((await scenario(patch)).reused, 'false');
  for (const patch of [{expired: true}, {size_in_bytes: 0}, {name: 'Other'}, {workflow_run: {head_sha: 'b'.repeat(40)}}])
    assert.equal((await scenario({}, patch)).reused, 'false');
  assert.equal((await scenario({}, {}, true)).reused, 'false');
  console.log('Device artifact reuse: exact source, owned repository, successful trusted run, live matching artifact and fail-open-to-build checks passed.');
})();
