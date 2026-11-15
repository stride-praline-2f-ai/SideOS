'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');

function requireThat(value, message) { if (!value) throw new Error(message); }
function sha(bytes) { return crypto.createHash('sha256').update(bytes).digest('hex'); }
function validateRequest(request) {
  for (const key of ['build', 'run_id', 'artifact_id']) requireThat(Number.isSafeInteger(request[key]) && request[key] > 0, `Invalid ${key}`);
  requireThat(typeof request.source_sha === 'string' && /^[a-f0-9]{40}$/.test(request.source_sha), 'Invalid source revision');
  for (const key of ['archive_sha256', 'ipa_sha256']) requireThat(typeof request[key] === 'string' && /^[a-f0-9]{64}$/.test(request[key]), `Invalid ${key}`);
  return request;
}
function validateProducer(request, run, artifact, repository) {
  requireThat(run.id === request.run_id && run.status === 'completed' && run.conclusion === 'success', 'The device build did not succeed');
  requireThat(run.head_sha === request.source_sha && run.head_repository?.full_name === repository, 'Wrong source or producer repository');
  requireThat(run.event === 'push' && run.head_branch === 'ipa/device' && run.path === '.github/workflows/private-build.yml', 'Untrusted producer workflow');
  requireThat(artifact.id === request.artifact_id && !artifact.expired && artifact.name === 'SideOS3-Device-IPA', 'Wrong or expired IPA artifact');
  requireThat(artifact.workflow_run?.id === request.run_id && artifact.workflow_run?.head_sha === request.source_sha, 'Artifact does not belong to the requested source build');
  requireThat(artifact.digest === `sha256:${request.archive_sha256}`, 'Artifact archive digest mismatch');
}
function validateManifest(request, manifest, verification, repository) {
  requireThat(manifest.sourceRevision === request.source_sha && String(manifest.build) === String(request.build), 'Manifest source/build mismatch');
  requireThat(manifest.repository === repository && manifest.unsigned === true, 'Wrong repository or signed artifact');
  requireThat(/^\d+\.\d+\.\d+$/.test(manifest.version), 'Invalid release version');
  requireThat(typeof manifest.ipa === 'string' && path.basename(manifest.ipa) === manifest.ipa, 'Invalid IPA filename');
  for (const field of ['nativeDisplayConfigurationVerified', 'duoLinkedSDKVerified', 'modernDesktopVerified', 'selfRefreshSourceGuardVerified', 'installerHostPickerPackaged', 'artifactPrivacyVerified', 'installerDependencyPolicyVerified', 'boundedIPAExtractionVerified', 'scopedSigningEntitlementsPreserved']) {
    requireThat(verification[field] === true, `Package verification missing: ${field}`);
  }
  requireThat(verification.maliciousGuestIsolationVerified === false, 'Do not claim malicious-guest isolation');
  for (const name of ['host', 'desktop', 'liveProcess', 'installer']) {
    const version = verification.linkedIOSSDKs?.[name];
    requireThat(typeof version === 'string' && /^\d+\.\d+\.\d+$/.test(version), `Missing actual linked SDK: ${name}`);
    const [major, minor] = version.split('.').map(Number);
    requireThat(major > 27 || major === 27 && minor >= 1, `Old linked SDK: ${name}`);
  }
}
function validateNotes(notes) {
  for (const credit of ['[SideInstaller by FrizzleM](https://github.com/FrizzleM/SideInstaller)',
    'https://github.com/LiveContainer/LiveContainer', 'https://github.com/StikDebug/StikJIT']) {
    requireThat(notes.includes(credit), 'Release notes must retain prominent upstream credits and official links');
  }
}

async function publish({github, context, core}) {
  requireThat(context.ref === 'refs/heads/release/publish', 'Run this workflow from the release/publish branch');
  const repository = `${context.repo.owner}/${context.repo.repo}`;
  const request = validateRequest(JSON.parse(fs.readFileSync('.github/release-request.json', 'utf8')));
  const api = {...context.repo};
  const run = (await github.rest.actions.getWorkflowRun({...api, run_id: request.run_id})).data;
  const artifact = (await github.rest.actions.getArtifact({...api, artifact_id: request.artifact_id})).data;
  validateProducer(request, run, artifact, repository);
  const download = await github.rest.actions.downloadArtifact({...api, artifact_id: request.artifact_id, archive_format: 'zip'});
  const archive = Buffer.from(download.data);
  requireThat(sha(archive) === request.archive_sha256, 'Downloaded archive bytes differ from the verified artifact');
  const temporary = fs.mkdtempSync(path.join(process.env.RUNNER_TEMP || os.tmpdir(), 'sideos-release-'));
  try {
    const zip = path.join(temporary, 'artifact.zip');
    const extracted = path.join(temporary, 'bundle'); fs.mkdirSync(extracted); fs.writeFileSync(zip, archive);
    // Read only the three expected leaf files. Never extract paths or symlinks
    // supplied by a ZIP archive into the runner's checkout.
    execFileSync('python3', ['-c', `
import pathlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    files=[item for item in archive.infolist() if not item.is_dir()]
    selected=[item for item in files if pathlib.PurePosixPath(item.filename).name in ('release.json','verification.json') or item.filename.endswith('.ipa')]
    assert len(selected)==3 and sum(item.filename.endswith('.ipa') for item in selected)==1
    names=[pathlib.PurePosixPath(item.filename).name for item in selected]
    assert len(set(names))==3 and 'release.json' in names and 'verification.json' in names
    for item,name in zip(selected,names):
        assert item.file_size <= (512*1024*1024 if name.endswith('.ipa') else 1024*1024)
        pathlib.Path(sys.argv[2],name).write_bytes(archive.read(item))
`, zip, extracted]);
    const manifest = JSON.parse(fs.readFileSync(path.join(extracted, 'release.json')));
    const verification = JSON.parse(fs.readFileSync(path.join(extracted, 'verification.json')));
    validateManifest(request, manifest, verification, repository);
    const original = path.join(extracted, manifest.ipa);
    requireThat(fs.existsSync(original) && sha(fs.readFileSync(original)) === request.ipa_sha256, 'IPA bytes differ from the verified build');
    const name = `SideOS-Build-${request.build}-unsigned.ipa`;
    fs.copyFileSync(original, path.join(temporary, name));
    for (const file of ['release.json', 'verification.json']) fs.copyFileSync(path.join(extracted, file), path.join(temporary, file));
    const files = [name, 'release.json', 'verification.json'];
    fs.writeFileSync(path.join(temporary, 'SHA256SUMS.txt'), files.map(file => `${sha(fs.readFileSync(path.join(temporary, file)))}  ${file}\n`).join(''));
    files.push('SHA256SUMS.txt');
    const tag = `v${manifest.version}-build.${request.build}`;
    // Never redirect an existing source tag to a different commit.
    let tagExists = false;
    try {
      await github.rest.git.getRef({...api, ref: `tags/${tag}`});
      tagExists = true;
    } catch (error) { if (error.status !== 404) throw error; }
    if (tagExists) {
      const tagged = (await github.rest.repos.getCommit({...api, ref: tag})).data;
      requireThat(tagged.sha === request.source_sha, 'Existing release tag points to another source revision');
    }
    const notes = fs.readFileSync('.github/release-notes.md', 'utf8')
      .replaceAll('{{SOURCE_SHA}}', request.source_sha).replaceAll('{{BUILD}}', String(request.build))
      .replaceAll('{{IPA_SHA256}}', request.ipa_sha256).replaceAll('{{REPOSITORY}}', repository);
    validateNotes(notes);
    const releases = await github.paginate(github.rest.repos.listReleases, {...api, per_page: 100});
    let release = releases.find(item => item.tag_name === tag);
    if (release) requireThat(release.target_commitish === request.source_sha, 'Existing release targets another source revision');
    else release = (await github.rest.repos.createRelease({...api, tag_name: tag, target_commitish: request.source_sha,
      name: `SideOS ${manifest.version} · Build ${request.build}`, body: notes, draft: true, prerelease: true, make_latest: 'false'})).data;
    let assets = await github.paginate(github.rest.repos.listReleaseAssets, {...api, release_id: release.id, per_page: 100});
    for (const file of files) {
      const bytes = fs.readFileSync(path.join(temporary, file)), digest = `sha256:${sha(bytes)}`;
      let asset = assets.find(item => item.name === file);
      if (!asset) asset = (await github.rest.repos.uploadReleaseAsset({...api, release_id: release.id, name: file, data: bytes,
        headers: {'content-type': file.endsWith('.ipa') ? 'application/octet-stream' : file.endsWith('.json') ? 'application/json' : 'text/plain', 'content-length': String(bytes.length)}})).data;
      requireThat(asset.size === bytes.length, `Uploaded asset size mismatch: ${file}`);
      if (asset.digest) requireThat(asset.digest === digest, `Uploaded asset checksum mismatch: ${file}`);
      else {
        const readback = await github.rest.repos.getReleaseAsset({...api, asset_id: asset.id, headers: {accept: 'application/octet-stream'}});
        requireThat(sha(Buffer.from(readback.data)) === sha(bytes), `Uploaded asset bytes mismatch: ${file}`);
      }
    }
    // The public release is the final mutation, after every asset is verified.
    release = (await github.rest.repos.updateRelease({...api, release_id: release.id, body: notes, draft: false, prerelease: true, make_latest: 'false'})).data;
    core.setOutput('release_url', release.html_url);
    core.setOutput('release_id', String(release.id));
    await core.summary.addHeading('Published experimental SideOS release').addLink('Release and IPA', release.html_url)
      .addRaw(`\n\nSource: ${request.source_sha}\n\nIPA SHA-256: ${request.ipa_sha256}\n`).write();
    core.info(`Published ${tag}: ${release.html_url}`);
  } finally { fs.rmSync(temporary, {recursive: true, force: true}); }
}
module.exports = publish;
module.exports.validateRequest = validateRequest;
module.exports.validateProducer = validateProducer;
module.exports.validateManifest = validateManifest;
module.exports.validateNotes = validateNotes;
