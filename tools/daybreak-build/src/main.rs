//! Builds Daybreak's quality presets from its one source pack.
//!
//! ```text
//! daybreak-build [--src pack/daybreak] [--presets presets.toml] [--out dist]
//!                [--check] [--pack] [--install <shaderpacks folder>]
//! ```
//!
//! Each preset in `presets.toml` becomes `<out>/<pack id>_<preset id>/`, a copy of the source
//! pack with its manifest and WGSL set for that preset. `--check` and `--pack` run
//! `horizon-shader check` and `pack` on each (the check the game and the registry run);
//! `--install` copies them into the game's `shaderpacks/`.

mod preset;

use preset::Presets;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const MANIFEST: &str = "horizon-shaders.toml";

struct Args {
    src: PathBuf,
    presets: PathBuf,
    out: PathBuf,
    check: bool,
    pack: bool,
    install: Option<PathBuf>,
}

fn args() -> Result<Args, String> {
    let mut args = Args {
        src: "pack/daybreak".into(),
        presets: "presets.toml".into(),
        out: "dist".into(),
        check: false,
        pack: false,
        install: None,
    };
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        let mut path = || it.next().map(PathBuf::from).ok_or(format!("{arg} needs a path"));
        match arg.as_str() {
            "--src" => args.src = path()?,
            "--presets" => args.presets = path()?,
            "--out" => args.out = path()?,
            "--install" => args.install = Some(path()?),
            "--check" => args.check = true,
            "--pack" => args.pack = true,
            "-h" | "--help" => {
                println!(
                    "daybreak-build [--src DIR] [--presets FILE] [--out DIR] [--check] [--pack] [--install DIR]"
                );
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument `{other}` (see --help)")),
        }
    }
    Ok(args)
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("daybreak-build: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let args = args()?;
    let read = |p: &Path| fs::read_to_string(p).map_err(|e| format!("{}: {e}", p.display()));
    let presets: Presets =
        toml::from_str(&read(&args.presets)?).map_err(|e| format!("{}: {e}", args.presets.display()))?;
    let manifest = read(&args.src.join(MANIFEST))?;
    let files = files(&args.src)?;

    for preset in &presets.preset {
        let text = preset.manifest(&manifest)?;
        let id = text
            .parse::<toml_edit::DocumentMut>()
            .ok()
            .and_then(|d| d["id"].as_str().map(str::to_owned))
            .ok_or("the built manifest has no id")?;
        let dir = args.out.join(&id);
        replace_dir(&dir)?;
        for rel in &files {
            let from = args.src.join(rel);
            let to = dir.join(rel);
            if let Some(parent) = to.parent() {
                fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
            }
            let write = |bytes: &[u8]| fs::write(&to, bytes).map_err(|e| format!("{}: {e}", to.display()));
            if rel == Path::new(MANIFEST) {
                write(text.as_bytes())?;
            } else if rel.extension().is_some_and(|e| e == "wgsl") {
                write(preset.wgsl(&read(&from)?).as_bytes())?;
            } else {
                fs::copy(&from, &to).map_err(|e| format!("{}: {e}", from.display()))?;
            }
        }
        println!("{id}: {}", dir.display());
        if args.check {
            horizon_shader("check", &dir)?;
        }
        if args.pack {
            horizon_shader("pack", &dir)?;
        }
        if let Some(packs) = &args.install {
            let target = packs.join(&id);
            replace_dir(&target)?;
            for rel in &files {
                let to = target.join(rel);
                if let Some(parent) = to.parent() {
                    fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
                }
                fs::copy(dir.join(rel), &to).map_err(|e| format!("{}: {e}", to.display()))?;
            }
            println!("  installed in {}", target.display());
        }
    }
    Ok(())
}

/// The files under `dir`, relative to it, in a fixed order.
fn files(dir: &Path) -> Result<Vec<PathBuf>, String> {
    fn walk(root: &Path, dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
        let entries = fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        for entry in entries {
            let path = entry.map_err(|e| e.to_string())?.path();
            if path.is_dir() {
                walk(root, &path, out)?;
            } else {
                out.push(path.strip_prefix(root).unwrap().to_path_buf());
            }
        }
        Ok(())
    }
    let mut out = Vec::new();
    walk(dir, dir, &mut out)?;
    out.sort();
    Ok(out)
}

/// Empties `dir` for a fresh build: only a folder this tool made (one with a manifest), so a
/// mistyped path never deletes anything else.
fn replace_dir(dir: &Path) -> Result<(), String> {
    if dir.exists() {
        if !dir.join(MANIFEST).is_file() {
            return Err(format!("{} exists and is not a shader pack: not replacing it", dir.display()));
        }
        fs::remove_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    }
    fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))
}

fn horizon_shader(command: &str, dir: &Path) -> Result<(), String> {
    let status = Command::new("horizon-shader")
        .arg(command)
        .arg(dir)
        .status()
        .map_err(|e| format!("horizon-shader (cargo install horizon-shader-api): {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("horizon-shader {command} {} failed", dir.display()))
    }
}
