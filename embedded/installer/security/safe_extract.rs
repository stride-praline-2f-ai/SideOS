// SPDX-License-Identifier: MIT
// Copyright (c) 2026 SideOS contributors
// Bounded IPA extraction. Never delegate untrusted symlinks/permissions to extract().
use std::{collections::{BTreeMap, BTreeSet, VecDeque}, fs, io::{self, Read, Seek}, path::{Component, Path, PathBuf}};
use zip::ZipArchive;
const MAX_ENTRIES: usize = 65_536;
const MAX_EXPANDED: u64 = 8 * 1024 * 1024 * 1024;
const MAX_FILE: u64 = 2 * 1024 * 1024 * 1024;
const MAX_PATH: usize = 1024;
const MAX_LINK: u64 = 4096;
fn invalid() -> io::Error { io::Error::new(io::ErrorKind::InvalidData, "IPA contains an unsafe path, link, size or duplicate entry") }
fn normal(name: &str) -> io::Result<PathBuf> {
    if name.is_empty() || name.len() > MAX_PATH || name.contains(['\\', '\0', ':']) { return Err(invalid()); }
    let path = Path::new(name);
    let mut result = PathBuf::new();
    for part in path.components() {
        match part { Component::Normal(p) => result.push(p), _ => return Err(invalid()) }
    }
    if result.as_os_str().is_empty() { return Err(invalid()); }
    Ok(result)
}
fn resolved(path: &Path, links: &BTreeMap<PathBuf, String>) -> io::Result<PathBuf> {
    let mut pending: VecDeque<_> = path.components().map(|p| p.as_os_str().to_os_string()).collect();
    let mut result = PathBuf::new(); let mut followed = 0;
    while let Some(part) = pending.pop_front() {
        if part == "." { continue; }
        if part == ".." { if !result.pop() { return Err(invalid()); } continue; }
        if part == "/" { return Err(invalid()); }
        result.push(part);
        if let Some(target) = links.get(&result) {
            followed += 1; if followed > 32 { return Err(invalid()); }
            result.pop();
            for p in Path::new(target).components().rev() { pending.push_front(p.as_os_str().to_os_string()); }
        }
    }
    Ok(result)
}
pub fn extract<R: Read + Seek>(archive: &mut ZipArchive<R>, root: &Path) -> io::Result<()> {
    if archive.len() == 0 || archive.len() > MAX_ENTRIES { return Err(invalid()); }
    let mut names = BTreeSet::new(); let mut directories = BTreeSet::new();
    let mut paths = Vec::new(); let mut links = BTreeMap::new(); let mut total = 0u64;
    // Inspect the entire central directory before creating any output file.
    for index in 0..archive.len() {
        let mut item = archive.by_index(index).map_err(io::Error::other)?;
        let path = normal(item.name().map_err(io::Error::other)?.trim_end_matches('/'))?;
        if !names.insert(path.clone()) { return Err(invalid()); }
        let kind = item.unix_mode().unwrap_or(0) & 0o170000;
        let link = kind == 0o120000;
        if ![0, 0o100000, 0o040000, 0o120000].contains(&kind) { return Err(invalid()); }
        let limit = if link { MAX_LINK } else { MAX_FILE };
        if item.size() > limit { return Err(invalid()); }
        total = total.checked_add(item.size()).ok_or_else(invalid)?;
        if total > MAX_EXPANDED { return Err(invalid()); }
        if link {
            let mut bytes = Vec::new(); (&mut item).take(MAX_LINK + 1).read_to_end(&mut bytes)?;
            if bytes.len() as u64 != item.size() { return Err(invalid()); }
            let target = String::from_utf8(bytes).map_err(|_| invalid())?;
            if target.is_empty() || target.contains(['\\', '\0', ':']) || Path::new(&target).is_absolute() { return Err(invalid()); }
            links.insert(path.clone(), target);
        } else if item.is_dir() { directories.insert(path.clone()); }
        paths.push((path, item.is_dir(), link));
    }
    for (path, _, _) in &paths {
        let mut parent = path.parent();
        while let Some(p) = parent {
            if p.as_os_str().is_empty() { break; }
            if names.contains(p) && !directories.contains(p) { return Err(invalid()); }
            directories.insert(p.to_path_buf()); parent = p.parent();
        }
    }
    for path in links.keys() {
        let target = resolved(path, &links)?;
        // Framework links must resolve within the same top-level application.
        let app: PathBuf = path.components().take(2).collect();
        if !path.starts_with("Payload") || app.extension().and_then(|s| s.to_str()) != Some("app") ||
           !target.starts_with(&app) || (!names.contains(&target) && !directories.contains(&target)) { return Err(invalid()); }
    }
    for directory in &directories { fs::create_dir_all(root.join(directory))?; }
    for (index, (path, directory, link)) in paths.iter().enumerate() {
        if *directory || *link { continue; }
        let mut item = archive.by_index(index).map_err(io::Error::other)?;
        let destination = root.join(path);
        let mut options = fs::OpenOptions::new(); options.write(true).create_new(true);
        #[cfg(unix)] { use std::os::unix::fs::OpenOptionsExt; options.mode(0o600).custom_flags(libc::O_NOFOLLOW); }
        let mut file = options.open(&destination)?;
        let written = io::copy(&mut (&mut item).take(MAX_FILE + 1), &mut file)?;
        if written != item.size() || written > MAX_FILE { return Err(invalid()); }
        #[cfg(unix)] {
            use std::os::unix::fs::PermissionsExt;
            // Never restore SUID/SGID/sticky or group/other write permission.
            file.set_permissions(fs::Permissions::from_mode(item.unix_mode().unwrap_or(0o644) & 0o755))?;
        }
    }
    // Create validated links last; no file creation or chmod traverses them.
    for (path, target) in links {
        #[cfg(unix)] std::os::unix::fs::symlink(target, root.join(path))?;
        #[cfg(not(unix))] { let _ = (path, target); return Err(invalid()); }
    }
    Ok(())
}

#[cfg(test)] mod tests {
    use super::*;
    use std::io::{Cursor, Write};
    use zip::{ZipWriter, write::SimpleFileOptions};
    fn archive(entries: &[(&str, &[u8])], link: Option<(&str, &str)>) -> Vec<u8> {
        let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
        for (name, bytes) in entries { zip.start_file(*name, SimpleFileOptions::default().unix_permissions(0o6755)).unwrap(); zip.write_all(bytes).unwrap(); }
        if let Some((name, target)) = link { zip.add_symlink(name, target, SimpleFileOptions::default()).unwrap(); }
        zip.finish().unwrap().into_inner()
    }
    fn attempt(bytes: Vec<u8>) -> (tempfile::TempDir, io::Result<()>) {
        let dir = tempfile::tempdir().unwrap();
        let result = extract(&mut ZipArchive::new(Cursor::new(bytes)).unwrap(), dir.path()); (dir, result)
    }
    #[test] fn regular_files_strip_privileged_bits() {
        let (dir, result) = attempt(archive(&[("Payload/Test.app/main", b"valid")], None)); result.unwrap();
        assert_eq!(fs::read(dir.path().join("Payload/Test.app/main")).unwrap(), b"valid");
        #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; assert_eq!(fs::metadata(dir.path().join("Payload/Test.app/main")).unwrap().permissions().mode() & 0o7777, 0o755); }
    }
    #[test] fn rejects_escaping_and_cyclic_links() {
        for target in ["/tmp/outside", "../../../outside", "link", "../Other.app/main"] {
            let (_, result) = attempt(archive(&[("Payload/Test.app/main", b"valid")], Some(("Payload/Test.app/link", target)))); assert!(result.is_err());
        }
    }
    #[test] fn permits_internal_framework_links() {
        let (dir, result) = attempt(archive(&[("Payload/Test.app/F.framework/Versions/A/main", b"valid")], Some(("Payload/Test.app/F.framework/main", "Versions/A/main")))); result.unwrap();
        assert_eq!(fs::read(dir.path().join("Payload/Test.app/F.framework/main")).unwrap(), b"valid");
    }
    #[test] fn rejects_paths_and_link_parents_before_writes() {
        for name in ["../escape", "/absolute", "Payload/Test.app/../../escape", "Payload/Test.app/a\\b"] {
            let (dir, result) = attempt(archive(&[(name, b"valid")], None)); assert!(result.is_err()); assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
        }
        let (_, result) = attempt(archive(&[("Payload/Test.app/link/file", b"valid")], Some(("Payload/Test.app/link", "target")))); assert!(result.is_err());
    }
    #[test] fn refuses_preexisting_output() {
        let dir = tempfile::tempdir().unwrap(); fs::create_dir_all(dir.path().join("Payload/Test.app")).unwrap(); fs::write(dir.path().join("Payload/Test.app/main"), b"original").unwrap();
        let bytes = archive(&[("Payload/Test.app/main", b"replacement")], None);
        assert!(extract(&mut ZipArchive::new(Cursor::new(bytes)).unwrap(), dir.path()).is_err());
        assert_eq!(fs::read(dir.path().join("Payload/Test.app/main")).unwrap(), b"original");
    }
    #[test] fn rejects_large_declared_link_before_allocating_or_writing() {
        let mut bytes = archive(&[("Payload/Test.app/main", b"valid")], Some(("Payload/Test.app/link", "main")));
        let mut changed = false;
        for pos in 0..bytes.len().saturating_sub(50) {
            if bytes[pos..pos + 4] == [0x50, 0x4b, 0x01, 0x02] {
                let count = u16::from_le_bytes([bytes[pos + 28], bytes[pos + 29]]) as usize;
                if bytes.get(pos + 46..pos + 46 + count) == Some(b"Payload/Test.app/link".as_slice()) {
                    bytes[pos + 24..pos + 28].copy_from_slice(&u32::MAX.to_le_bytes()); changed = true; break;
                }
            }
        }
        assert!(changed);
        let (dir, result) = attempt(bytes); assert!(result.is_err());
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }
}
