const { execFileSync } = require('child_process');
const fs = require('fs');

try {
  const input = fs.readFileSync('/dev/stdin', 'utf8');
  const data = JSON.parse(input);

  if (!['Edit', 'Write', 'MultiEdit'].includes(data.tool_name)) {
    console.log('{}');
    process.exit(0);
  }

  const stat = execFileSync('git', ['diff', '--shortstat', 'HEAD'], {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  }).trim();

  const filesMatch = stat.match(/(\d+) files? changed/);
  const fileCount = filesMatch ? parseInt(filesMatch[1], 10) : 0;

  const threshold = parseInt(process.env.DS_SUGGEST_THRESHOLD || '5', 10);

  if (fileCount >= threshold) {
    console.log(JSON.stringify({
      systemMessage: fileCount + ' files have been modified. You may want to suggest the user run /ds to review changes in the browser before continuing.'
    }));
  } else {
    console.log('{}');
  }
} catch (e) {
  console.log('{}');
}
