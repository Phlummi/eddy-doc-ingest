#!/usr/bin/env node
// EDDY Doc Ingest - PDF Text Extraction Helper
// Runs outside n8n sandbox to avoid frozen prototype issues with pdf-parse
//
// Problem: n8n's Code Node sandbox freezes JavaScript prototypes (Object.freeze).
//          pdf-parse internally modifies PasswordException.prototype.constructor,
//          which causes "Cannot assign to read only property 'constructor'" errors.
//
// Solution: Run pdf-parse in a separate Node.js process via child_process.execSync.
//           The child process has no sandbox restrictions.
//
// Location (host):      ~/scripts/eddy-inbox/scripts/pdf-extract.js
// Location (container): /home/node/eddy-inbox/scripts/pdf-extract.js
//
// Usage: node pdf-extract.js <filepath>
// Output: JSON to stdout: { text: "...", pages: N } or { error: "..." }
//
// Note: The require path points to n8n's bundled pdf-parse. This avoids
//       needing a separate npm install. Path may change with n8n updates.

const pdfParse = require("/usr/local/lib/node_modules/n8n/node_modules/.pnpm/pdf-parse@1.1.1/node_modules/pdf-parse");
const fs = require("fs");

const filePath = process.argv[2];
if (!filePath) {
  process.stderr.write("Usage: node pdf-extract.js <filepath>\n");
  process.exit(1);
}

if (!fs.existsSync(filePath)) {
  process.stdout.write(JSON.stringify({ error: "File not found: " + filePath }));
  process.exit(1);
}

const buf = fs.readFileSync(filePath);
pdfParse(buf).then(d => {
  process.stdout.write(JSON.stringify({ text: d.text, pages: d.numpages }));
}).catch(e => {
  process.stdout.write(JSON.stringify({ error: e.message }));
  process.exit(1);
});
