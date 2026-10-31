#!/bin/bash
# make_lab.sh - Bough QA data factory (test plan Phase 3.3a).
#
# Builds every "zoo animal" repository under /tmp/bough-lab for the Phase 2
# test cases. Writes ONLY under the lab root; delete the directory to roll back.
#
# Usage:
#   ./Scripts/qa/make_lab.sh                     # build everything at /tmp/bough-lab
#   ./Scripts/qa/make_lab.sh /tmp/my-lab         # custom root
#   ./Scripts/qa/make_lab.sh --only weird        # rebuild a single animal (no clean)
#
# Animals:
#   topology     known graph (fork + merge + topic)           -> F3-01/02
#   c2001        2001 commits (history truncation boundary)   -> F3-03
#   weird        filenames: space/quote/emoji/newline/latin1  -> F2-08
#   bigdiff      ~7000-line diff (truncation boundary)        -> F3-05
#   files10k     10,000 tracked files + dirty tail            -> F2-10
#   bomb         10000x10000 PNG (decode bomb)                -> F3-08
#   skew         author date != committer date                -> F3-09
#   conf_markers marker-like content in CLEAN files            -> F5-05
#   conf_active  merge conflict left open (default style)     -> F5-01/02
#   conf_diff3   merge conflict left open (diff3 style)       -> F5-04
#   conf_binary  binary merge conflict left open              -> F5-08
#   r1..r50      clone + bare origin (ahead 1, r1-r10 dirty)  -> F8-01/02
#   bad_head     HEAD points to a ghost branch                -> F8-03
#   bad_perm     .git chmod 000                               -> F8-03
#   zoo_bare.git bare repository directory                    -> C5
#   zoo_detached detached HEAD                                -> C5
#   zoo_badhead  HEAD -> nonexistent branch                   -> C5
#   zoo_empty    empty repository (unborn HEAD)               -> C5/F2-14
#   zoo_broken   .git/refs deleted                            -> C5
set -euo pipefail

LAB="/tmp/bough-lab"
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    *) LAB="$1"; shift ;;
  esac
done

# Defensive input validation (dev-controlled QA args; guards the g()/rm paths below).
case "$LAB" in
  /*) : ;;
  *) echo "error: LAB must be an absolute path, got: $LAB" >&2; exit 2 ;;
esac
if [ "$LAB" = "/" ]; then
  echo "error: refusing / as lab root" >&2
  exit 2
fi
if [ -n "$ONLY" ]; then
  case "$ONLY" in
    [a-z0-9_-]*) : ;;
    *) echo "error: --only must match [a-z0-9_-], got: $ONLY" >&2; exit 2 ;;
  esac
fi

# Fixed identity for every commit so tests never depend on the machine's git config.
GIT_ID=(-c user.name=QA -c user.email=qa@lab.local -c init.defaultBranch=main)
g() { git "${GIT_ID[@]}" "$@"; }

# Full-build clean. bad_perm chmods .git to 000, which blocks plain rm -rf.
if [ -z "$ONLY" ]; then
  [ -d "$LAB" ] && chmod -R u+rwX "$LAB" 2>/dev/null || true
  rm -rf "$LAB"
fi
mkdir -p "$LAB"

repo_topology() {
  local d="$LAB/topology"
  g init -q "$d"
  (
    cd "$d"
    echo 1 > f.txt; g add .; g commit -qm c1
    echo 2 > g.txt; g add .; g commit -qm c2
    g checkout -qb feat
    echo x >> f.txt; g add .; g commit -qm feat-1
    g checkout -q main
    echo y > h.txt; g add .; g commit -qm main-1
    g merge -q --no-ff -m "merge feat" feat
    g checkout -qb topic HEAD~1
    echo z > t.txt; g add .; g commit -qm topic-1
  )
}

repo_2001() {
  local d="$LAB/c2001"
  g init -q "$d"
  (
    cd "$d"
    echo 0 > f.txt; g add .; g commit -qm c0
    local i
    for i in $(seq 1 2001); do
      echo "$i" >> f.txt
      g commit -qam "c$i"
      if [ $((i % 500)) -eq 0 ]; then echo "    ...c$i"; fi
    done
  )
}

repo_weird_names() {
  local d="$LAB/weird"
  g init -q "$d"
  (
    cd "$d"
    : > "space name.txt"
    : > "quote'single.txt"
    : > 'quote"double.txt'
    : > "中文 🚀.txt"
    : > 'back\slash.txt'
    : > $'new\nline.txt'
    : > $'nfd cafe\xCC\x81.txt'   # combining acute (NFD), APFS-safe legacy-encoding animal
    g add -A
    g commit -qm "weird names"
  )
}

repo_big_diff() {
  local d="$LAB/bigdiff"
  g init -q "$d"
  (
    cd "$d"
    seq 1 1000 > f.txt; g add .; g commit -qm base
    seq 1 7000 > f.txt
    g add .; g commit -qm "big change"
  )
}

repo_files10k() {
  local d="$LAB/files10k"
  g init -q "$d"
  (
    cd "$d"
    mkdir -p src
    touch src/file{1..10000}.txt
    g add .; g commit -qm "10k files"
    echo changed > src/file1.txt
    echo changed > src/file100.txt
    echo changed > src/file9999.txt
    : > src/untracked_new.txt
  )
}

repo_bomb() {
  local d="$LAB/bomb"
  local gen="/tmp/bough_qa_png_gen.swift"
  local src="$LAB/.tmp_src.png"
  cat > "$gen" <<'SWIFT'
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let size = 512
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.85, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
srand48(42)
for _ in 0..<600 {
    let r = CGFloat(drand48()) * 40 + 4
    let x = CGFloat(drand48()) * CGFloat(size)
    let y = CGFloat(drand48()) * CGFloat(size)
    ctx.setFillColor(CGColor(red: CGFloat(drand48()), green: CGFloat(drand48()),
                             blue: CGFloat(drand48()), alpha: 0.8))
    ctx.fill(CGRect(x: x, y: y, width: r, height: r))
}
let img = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let dest = CGImageDestinationCreateWithURL(out, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("png write failed") }
SWIFT
  g init -q "$d"
  xcrun swift "$gen" "$src"
  sips -z 10000 10000 "$src" --out "$d/big.png" > /dev/null
  ( cd "$d"; g add .; g commit -qm "10000x10000 decode bomb" )
  rm -f "$src"
}

repo_skew() {
  local d="$LAB/skew"
  g init -q "$d"
  (
    cd "$d"
    echo a > f.txt; g add .
    GIT_AUTHOR_DATE="2026-01-01T10:00:00+08:00" \
    GIT_COMMITTER_DATE="2026-01-02T10:00:00+08:00" \
      g commit -qm "author 01-01 / committer 01-02"
    echo b >> f.txt; g add .
    GIT_AUTHOR_DATE="2026-03-01T10:00:00+08:00" \
    GIT_COMMITTER_DATE="2026-02-01T10:00:00+08:00" \
      g commit -qm "author 03-01 / committer 02-01"
  )
}

repo_conf_markers() {
  local d="$LAB/conf_markers"
  g init -q "$d"
  (
    cd "$d"
    printf 'let s = "<<<<<<< looks like a marker"\n' > a.swift
    printf 'text\n=======\nno closing marker below\n' > b.txt
    printf '<<<<<<<\n<<<<<<<\ndoubly opened\n' > c.txt
    g add .; g commit -qm "marker-like content, clean tree"
  )
}

repo_conf_active() {
  local d="$LAB/conf_active"
  g init -q "$d"
  (
    cd "$d"
    printf 'line1\nline2\nline3\n' > c.txt
    g add .; g commit -qm base
    g checkout -qb side
    printf 'line1\nside\nline3\n' > c.txt
    g commit -qam "side edit"
    g checkout -q main
    printf 'line1\nmine\nline3\n' > c.txt
    g commit -qam "main edit"
    # Leave the repo mid-conflict on purpose (F5-01/02).
    g merge side || true
  )
}

repo_conf_diff3() {
  local d="$LAB/conf_diff3"
  g init -q "$d"
  (
    cd "$d"
    g config merge.conflictStyle diff3
    printf 'line1\nline2\nline3\n' > c.txt
    g add .; g commit -qm base
    g checkout -qb side
    printf 'line1\nside\nline3\n' > c.txt
    g commit -qam "side edit"
    g checkout -q main
    printf 'line1\nmine\nline3\n' > c.txt
    g commit -qam "main edit"
    g merge side || true   # conflict carries the ||||||| base section
  )
}

repo_conf_binary() {
  local d="$LAB/conf_binary"
  g init -q "$d"
  (
    cd "$d"
    head -c 1024 /dev/urandom > img.bin
    g add .; g commit -qm base
    g checkout -qb side
    head -c 1024 /dev/urandom > img.bin; g commit -qam "side bin"
    g checkout -q main
    head -c 1024 /dev/urandom > img.bin; g commit -qam "main bin"
    g merge side || true
  )
}

repo_50() {
  local i d o
  for i in $(seq 1 50); do
    o="$LAB/r$i-origin.git"
    d="$LAB/r$i"
    g init -q --bare "$o"
    g clone -q "$o" "$d" 2>/dev/null
    (
      cd "$d"
      echo "$i" > f.txt; g add .; g commit -qm "c$i"
      g push -q -u origin main
      echo "$i-local" >> f.txt; g commit -qam "c$i-local"   # ahead 1
    )
    if [ "$i" -le 10 ]; then echo dirty >> "$d/f.txt"; fi    # r1-r10 dirty
  done
}

repo_bad() {
  local d="$LAB/bad_head"
  g init -q "$d"
  ( cd "$d"; echo 1 > a; g add .; g commit -qm one )
  printf 'ref: refs/heads/ghost\n' > "$d/.git/HEAD"

  local d2="$LAB/bad_perm"
  g init -q "$d2"
  ( cd "$d2"; echo 1 > a; g add .; g commit -qm one )
  chmod 000 "$d2/.git"
}

repo_zoo() {
  g init -q --bare "$LAB/zoo_bare.git"

  local d="$LAB/zoo_detached"
  g init -q "$d"
  ( cd "$d"
    echo 1 > a; g add .; g commit -qm one
    echo 2 > a; g commit -qam two
    g checkout -q HEAD~1 )

  d="$LAB/zoo_badhead"
  g init -q "$d"
  ( cd "$d"; echo 1 > a; g add .; g commit -qm one )
  printf 'ref: refs/heads/nope\n' > "$d/.git/HEAD"

  g init -q "$LAB/zoo_empty"

  d="$LAB/zoo_broken"
  g init -q "$d"
  ( cd "$d"; echo 1 > a; g add .; g commit -qm one )
  rm -rf "$d/.git/refs"
}

maybe() {
  local name="$1"; shift
  if [ -z "$ONLY" ] || [ "$ONLY" = "$name" ]; then
    echo "==> $name"
    "$@"
  fi
}

START=$(date +%s)
maybe topology     repo_topology
maybe c2001        repo_2001
maybe weird        repo_weird_names
maybe bigdiff      repo_big_diff
maybe files10k     repo_files10k
maybe bomb         repo_bomb
maybe skew         repo_skew
maybe conf_markers repo_conf_markers
maybe conf_active  repo_conf_active
maybe conf_diff3   repo_conf_diff3
maybe conf_binary  repo_conf_binary
maybe r1-r50       repo_50
maybe bad          repo_bad
maybe zoo          repo_zoo

echo
echo "lab ready: $LAB (built in $(( $(date +%s) - START ))s)"
ls -1 "$LAB"
