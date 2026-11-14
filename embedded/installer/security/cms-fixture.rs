// SPDX-License-Identifier: MIT
// Synthetic signing fixture. No developer signing material is used.
use crate::{CmsSigner, CmsSigningRequest, EncodedCodeDirectory, HashAlgorithm, RustCryptoCmsSigner};
use std::{fs, process::Command, path::PathBuf};
struct Scratch(PathBuf);
impl Drop for Scratch { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }
#[test]
fn cms_signature_verifies_independently_and_rejects_tampering() {
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let path = std::env::temp_dir().join(format!("sideos-cms-fixture-{}-{stamp}", std::process::id()));
    let mut builder = fs::DirBuilder::new();
    #[cfg(unix)] { use std::os::unix::fs::DirBuilderExt; builder.mode(0o700); }
    builder.create(&path).unwrap();
    let dir = Scratch(path); let root = &dir.0;
    let run = |args: &[&str]| Command::new("openssl").current_dir(root).args(args).output().expect("OpenSSL is required for the independent signature fixture");
    assert!(run(&["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=SideOS Signing Fixture", "-days", "1", "-keyout", "key.pem", "-out", "cert.pem"]).status.success());
    assert!(run(&["pkcs8", "-topk8", "-nocrypt", "-in", "key.pem", "-outform", "DER", "-out", "key.der"]).status.success());
    assert!(run(&["x509", "-in", "cert.pem", "-outform", "DER", "-out", "cert.der"]).status.success());
    let signer = RustCryptoCmsSigner::from_der(&fs::read(root.join("key.der")).unwrap(), &fs::read(root.join("cert.der")).unwrap(), std::iter::empty::<&[u8]>()).unwrap();
    let content = b"SideOS synthetic CodeDirectory fixture";
    let directories = [EncodedCodeDirectory { algorithm: HashAlgorithm::Sha256, bytes: content }];
    fs::write(root.join("content"), content).unwrap();
    fs::write(root.join("signature.der"), signer.sign(CmsSigningRequest { code_directories: &directories }).unwrap()).unwrap();
    assert!(run(&["cms", "-verify", "-binary", "-noverify", "-inform", "DER", "-in", "signature.der", "-content", "content", "-out", "verified"]).status.success(), "Independent OpenSSL verifier rejected the generated CMS signature");
    assert_eq!(fs::read(root.join("verified")).unwrap(), content);
    fs::write(root.join("content"), b"changed content").unwrap();
    assert!(!run(&["cms", "-verify", "-binary", "-noverify", "-inform", "DER", "-in", "signature.der", "-content", "content", "-out", "rejected"]).status.success(), "Tampered signing content was accepted");
}
