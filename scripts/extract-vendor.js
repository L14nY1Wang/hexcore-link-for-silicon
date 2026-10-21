#!/usr/bin/env node
'use strict';
// Extract the vendor's app.asar into packdir/ for build-arm64.sh.
//
// The 2.5.9 archive predates the current asar header rules (file offsets are
// numbers, and the header carries decoy entries), so @electron/asar refuses it.
// Parse the archive directly instead. Files marked `unpacked` are copied from
// the app.asar.unpacked tree next to the archive.
//
// Usage: node scripts/extract-vendor.js ["/Applications/Hexcore Link.app"] [packdir]
const fs = require('fs');
const path = require('path');

const appDir = process.argv[2] || '/Applications/Hexcore Link.app';
const outDir = path.resolve(process.argv[3] || 'packdir');
const asarPath = path.join(appDir, 'Contents/Resources/app.asar');
const unpackedDir = `${asarPath}.unpacked`;

if (!fs.existsSync(asarPath)) {
  console.error(`not found: ${asarPath}`);
  process.exit(1);
}
const data = fs.readFileSync(asarPath);
if (data.readUInt32LE(0) !== 4) {
  console.error(`not an asar archive: ${asarPath}`);
  process.exit(1);
}
const headerSize = data.readUInt32LE(4);
const header = JSON.parse(data.subarray(16, 16 + headerSize - 8).toString('utf8'));
const base = 8 + headerSize;

let files = 0;
let unpacked = 0;

function walk(node, prefix) {
  for (const [name, entry] of Object.entries(node.files || {})) {
    const rel = path.join(prefix, name);
    if (rel.split(path.sep).includes('..')) continue;
    if (entry.files) {
      fs.mkdirSync(path.join(outDir, rel), { recursive: true });
      walk(entry, rel);
      continue;
    }
    const dest = path.join(outDir, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });

    if (entry.unpacked) {
      const src = path.join(unpackedDir, rel);
      if (fs.existsSync(src)) {
        fs.copyFileSync(src, dest);
        unpacked++;
      }
      continue;
    }

    const offset = Number(entry.offset);
    const size = Number(entry.size);
    // Decoy entries carry impossible offsets/sizes; skip them.
    if (!Number.isFinite(offset) || !Number.isFinite(size) ||
        offset < 0 || size < 0 || base + offset + size > data.length) continue;

    fs.writeFileSync(dest, data.subarray(base + offset, base + offset + size));
    files++;
  }
}

fs.mkdirSync(outDir, { recursive: true });
walk(header, '');

// The locale bundles and the app icon live outside app.asar. The preloads read
// locales relative to dist/../locales, and the bundle needs the icon for Dock.
const resDir = path.join(appDir, 'Contents/Resources');
if (fs.existsSync(path.join(resDir, 'locales'))) {
  fs.cpSync(path.join(resDir, 'locales'), path.join(outDir, 'locales'), { recursive: true });
}
if (fs.existsSync(path.join(resDir, 'icon.icns'))) {
  fs.copyFileSync(path.join(resDir, 'icon.icns'), path.join(outDir, 'icon.icns'));
}
console.log(`extracted ${files} files (${unpacked} unpacked) into ${outDir}`);
