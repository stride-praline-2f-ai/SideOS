'use strict';
const assert = require('node:assert/strict');
const {validateRequest, validateProducer, validateManifest, validateNotes} = require('./publish-release.cjs');
const request = {build: 13, run_id: 120, artifact_id: 300, source_sha: 'a'.repeat(40), archive_sha256: 'b'.repeat(64), ipa_sha256: 'c'.repeat(64)};
const repository = 'example/SideOS';
const run = {id: 120, status: 'completed', conclusion: 'success', head_sha: request.source_sha,
  head_repository: {full_name: repository}, event: 'push', head_branch: 'ipa/device', path: '.github/workflows/private-build.yml'};
const artifact = {id: 300, expired: false, name: 'SideOS3-Device-IPA', workflow_run: {id: 120, head_sha: request.source_sha}, digest: `sha256:${request.archive_sha256}`};
const verification = {nativeDisplayConfigurationVerified: true, duoLinkedSDKVerified: true, modernDesktopVerified: true,
  selfRefreshSourceGuardVerified: true, installerHostPickerPackaged: true,
  artifactPrivacyVerified: true, installerDependencyPolicyVerified: true, boundedIPAExtractionVerified: true,
  scopedSigningEntitlementsPreserved: true, maliciousGuestIsolationVerified: false,
  linkedIOSSDKs: {host: '27.2.0', desktop: '27.2.0', liveProcess: '27.2.0', installer: '27.2.0'}};
const manifest = {sourceRevision: request.source_sha, build: '13', repository, unsigned: true, version: '3.1.0', ipa: 'SideOS-unsigned.ipa'};
validateRequest(request); validateProducer(request, run, artifact, repository); validateManifest(request, manifest, verification, repository);
const credits = '[SideInstaller by FrizzleM](https://github.com/FrizzleM/SideInstaller)\nhttps://github.com/LiveContainer/LiveContainer\nhttps://github.com/StikDebug/StikJIT';
validateNotes(credits);
assert.throws(() => validateNotes('SideOS release with no credits'));
for (const change of [{build: -1}, {run_id: 0}, {artifact_id: 1.2}, {source_sha: 'main'}, {archive_sha256: 'bad'}, {ipa_sha256: ''}]) {
  assert.throws(() => validateRequest({...request, ...change}));
}
for (const change of [{conclusion: 'failure'}, {status: 'in_progress'}, {head_sha: 'd'.repeat(40)}, {event: 'pull_request'},
  {head_branch: 'main'}, {path: '.github/workflows/untrusted.yml'}, {head_repository: {full_name: 'other/SideOS'}}]) {
  assert.throws(() => validateProducer(request, {...run, ...change}, artifact, repository));
}
for (const change of [{expired: true}, {id: 301}, {name: 'Build logs'}, {workflow_run: {id: 121, head_sha: request.source_sha}}, {digest: 'sha256:wrong'}]) {
  assert.throws(() => validateProducer(request, run, {...artifact, ...change}, repository));
}
for (const change of [{sourceRevision: 'd'.repeat(40)}, {build: '12'}, {repository: 'other/SideOS'}, {unsigned: false}, {version: '../main'}, {ipa: '../other.ipa'}]) {
  assert.throws(() => validateManifest(request, {...manifest, ...change}, verification, repository));
}
for (const name of Object.keys(verification.linkedIOSSDKs)) {
  assert.throws(() => validateManifest(request, manifest, {...verification, linkedIOSSDKs: {...verification.linkedIOSSDKs, [name]: '26.2.0'}}, repository));
}
for (const field of ['duoLinkedSDKVerified', 'selfRefreshSourceGuardVerified', 'installerHostPickerPackaged']) {
  assert.throws(() => validateManifest(request, manifest, {...verification, [field]: false}, repository));
}
console.log('Release publisher safeguards: exact successful owned build, immutable archive/IPA hashes, device SDKs, source manifests and refresh/picker verification passed.');

// Exercise publication order with a real local ZIP and a mocked GitHub API.
// No credentials, network calls, release mutations or real application bytes.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path'), crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const publish = require('./publish-release.cjs');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
async function publicationOrder() {
  const cwd = process.cwd(), temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'sideos-release-test-'));
  try {
    process.chdir(temporary); fs.mkdirSync('.github'); fs.mkdirSync('payload');
    const ipa = Buffer.from('Synthetic release-test bytes, not an application');
    fs.writeFileSync('payload/' + manifest.ipa, ipa);
    fs.writeFileSync('payload/release.json', JSON.stringify(manifest));
    fs.writeFileSync('payload/verification.json', JSON.stringify(verification));
    execFileSync('python3', ['-c', "import pathlib,zipfile\nwith zipfile.ZipFile('artifact.zip','w') as z:\n for p in pathlib.Path('payload').iterdir():z.write(p,p.name)\n"]);
    const archive = fs.readFileSync('artifact.zip');
    const exact = {...request, archive_sha256: hash(archive), ipa_sha256: hash(ipa)};
    const exactArtifact = {...artifact, digest: 'sha256:' + exact.archive_sha256};
    fs.writeFileSync('.github/release-notes.md', credits);
    const events = [];
    const summary = {addHeading(){return this;}, addLink(){return this;}, addRaw(){return this;}, async write(){}};
    const github = {rest: {
      git: {async getRef(){throw Object.assign(new Error('No existing tag ref'), {status:404});}},
      actions: {async getWorkflowRun(){return {data:run};}, async getArtifact(){return {data:exactArtifact};}, async downloadArtifact(){return {data:archive};}},
      repos: {
        listReleases(){}, listReleaseAssets(){},
        async getCommit(){throw Object.assign(new Error('No existing tag'), {status:404});},
        async createRelease(options){assert.equal(options.draft,true); assert.equal(options.target_commitish,exact.source_sha); events.push('draft'); return {data:{id:1, html_url:'https://example.test/release', target_commitish:exact.source_sha}};},
        async uploadReleaseAsset(options){events.push('upload:'+options.name); return {data:{id:events.length, name:options.name, size:options.data.length, digest:'sha256:'+hash(options.data)}};},
        async updateRelease(options){assert.equal(events.filter(e=>e.startsWith('upload:')).length,4); assert.equal(options.draft,false); assert.equal(options.prerelease,true); events.push('public'); return {data:{id:1,html_url:'https://example.test/release'}};}
      }}, async paginate(){return []}};
    const args = {github, context:{repo:{owner:'example',repo:'SideOS'},ref:'refs/heads/release/publish'}, core:{setOutput(){},info(){},summary}};
    fs.writeFileSync('.github/release-request.json',JSON.stringify(exact));
    await publish(args);
    assert.equal(events[0],'draft'); assert.equal(events.at(-1),'public'); assert.equal(events.length,6);
    events.length = 0;
    fs.writeFileSync('.github/release-request.json',JSON.stringify({...exact,ipa_sha256:'d'.repeat(64)}));
    await assert.rejects(publish(args), /IPA bytes differ/); assert.deepEqual(events,[]);
    fs.writeFileSync('.github/release-request.json',JSON.stringify(exact));
    fs.writeFileSync('.github/release-notes.md','Release without author links');
    await assert.rejects(publish(args), /upstream credits/); assert.deepEqual(events,[]);
    console.log('Release publication order passed: verified files first, draft uploads second, public mutation last; corrupt IPA and missing-credit cases make no release mutation.');
  } finally { process.chdir(cwd); fs.rmSync(temporary,{recursive:true,force:true}); }
}
publicationOrder().catch(error => { console.error(error); process.exitCode = 1; });
