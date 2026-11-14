// Exact-source artifact reuse avoids allocating another Mac for an existing IPA.
module.exports = async function reuseDeviceIPA({github, context, core}) {
  core.setOutput('reused', 'false');
  try {
    const repository = `${context.repo.owner}/${context.repo.repo}`;
    const {data} = await github.rest.actions.listWorkflowRuns({
      ...context.repo, workflow_id: 'private-build.yml', head_sha: context.sha,
      status: 'success', per_page: 30
    });
    for (const run of data.workflow_runs) {
      if (run.id === context.runId || run.head_sha !== context.sha || run.conclusion !== 'success' ||
          run.head_repository?.full_name !== repository ||
          !((run.event === 'push' && run.head_branch === 'ipa/device') || run.event === 'workflow_dispatch')) continue;
      const artifacts = await github.rest.actions.listWorkflowRunArtifacts({...context.repo, run_id: run.id, per_page: 100});
      const artifact = artifacts.data.artifacts.find(a => a.name === 'SideOS3-Device-IPA' && !a.expired &&
        a.size_in_bytes > 0 && a.workflow_run?.head_sha === context.sha);
      if (!artifact) continue;
      const url = `https://github.com/${repository}/actions/runs/${run.id}/artifacts/${artifact.id}`;
      core.setOutput('reused', 'true'); core.setOutput('artifact_url', url);
      await core.summary.addHeading('Existing device IPA reused').addLink('Download verified IPA', url)
        .addRaw(`\n\nSource: ${context.sha}. No Mac build was started.\n`).write();
      return;
    }
  } catch (error) { core.info('Artifact reuse lookup unavailable; running normal validation and build.'); }
};
