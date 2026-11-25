'use strict';
const fs = require('fs');
const path = require('path');
const a = fs.readFileSync(path.join(__dirname, '../cloud/services/protocol.js'));
const b = fs.readFileSync(path.join(__dirname, '../desktop/agent/protocol.js'));
if (!a.equals(b)) { console.error('FAIL: protocol.js differs between cloud and desktop'); process.exit(1); }
console.log('OK: protocol.js identical in cloud and desktop');
