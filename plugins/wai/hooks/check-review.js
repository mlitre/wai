const fs = require('fs');
const path = require('path');

try {
  var cwd = process.cwd();
  var dsDir = path.join(cwd, '.ds');
  var serverInfoPath = path.join(dsDir, 'server-info');

  if (!fs.existsSync(serverInfoPath)) {
    console.log('{}');
    process.exit(0);
  }

  var serverInfo = JSON.parse(fs.readFileSync(serverInfoPath, 'utf8'));
  var stateDir = serverInfo.state_dir;

  if (!stateDir) {
    console.log('{}');
    process.exit(0);
  }

  var reviewPath = path.join(stateDir, 'review.json');

  // Atomic claim: rename before reading so a concurrent consumer (the /ds
  // skill's long-poll curl, another hook invocation) can't double-deliver.
  // If the rename fails the file is gone or never existed, do nothing.
  var claimPath = path.join(stateDir, '.review.claimed.' + process.pid + '.' + Date.now());
  try {
    fs.renameSync(reviewPath, claimPath);
  } catch (e) {
    console.log('{}');
    process.exit(0);
  }

  var review;
  try {
    review = JSON.parse(fs.readFileSync(claimPath, 'utf8'));
  } finally {
    try { fs.unlinkSync(claimPath); } catch (e) {}
  }

  var msg = 'Diffscape review submitted: ' + review.decision.toUpperCase();

  if (review.summary) {
    msg += '\nSummary: ' + review.summary;
  }

  if (review.comments && review.comments.length > 0) {
    msg += '\n\nComments:';
    review.comments.forEach(function (c, i) {
      var location = c.type === 'inline'
        ? c.file + ':' + c.line
        : c.file + ' (file-level)';
      msg += '\n' + (i + 1) + '. **' + location + '**, ' + c.body;
    });
  }

  console.log(JSON.stringify({ systemMessage: msg }));
} catch (e) {
  console.log('{}');
}
