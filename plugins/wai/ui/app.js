// Diffscape, Client-side code review application

(function () {
  'use strict';

  const state = {
    rawDiff: '',
    rawFilePatches: [], // array of per-file raw-diff slices (includes git metadata)
    baseline: 'HEAD',
    files: [],       // parsed file objects from diff2html
    comments: [],    // { id, file, line, body, type: 'inline' | 'file-level' }
    viewMode: localStorage.getItem('ds-view-mode') || 'line-by-line',
    submitted: false,
    collapsedFiles: {}, // idx -> true
    focusedFileIdx: 0,
  };

  let commentIdCounter = 0;
  let heartbeatId = null;
  const HEARTBEAT_INTERVAL_MS = 60 * 1000;

  function startHeartbeat() {
    if (heartbeatId !== null) return;
    heartbeatId = setInterval(function () {
      fetch('/api/heartbeat').catch(function () {});
    }, HEARTBEAT_INTERVAL_MS);
  }

  function stopHeartbeat() {
    if (heartbeatId !== null) {
      clearInterval(heartbeatId);
      heartbeatId = null;
    }
  }

  // DOM references
  const dom = {
    baselineInfo: document.getElementById('baseline-info'),
    fileSummary: document.getElementById('file-summary'),
    btnUnified: document.getElementById('btn-unified'),
    btnSplit: document.getElementById('btn-split'),
    btnApprove: document.getElementById('btn-approve'),
    btnRequestChanges: document.getElementById('btn-request-changes'),
    sidebar: document.getElementById('sidebar'),
    btnToggleSidebar: document.getElementById('btn-toggle-sidebar'),
    fileList: document.getElementById('file-list'),
    diffContainer: document.getElementById('diff-container'),
    diffs: document.getElementById('diffs'),
    loading: document.getElementById('loading'),
    emptyState: document.getElementById('empty-state'),
    reviewModal: document.getElementById('review-modal'),
    modalTitle: document.getElementById('modal-title'),
    reviewSummary: document.getElementById('review-summary'),
    commentSummaryEl: document.getElementById('comment-summary'),
    modalCancel: document.getElementById('modal-cancel'),
    modalApprove: document.getElementById('modal-approve'),
    modalRequestChanges: document.getElementById('modal-request-changes'),
    submittedOverlay: document.getElementById('submitted-overlay'),
    submittedText: document.getElementById('submitted-text'),
    headerCommentCount: document.getElementById('header-comment-count'),
    fileSearch: document.getElementById('file-search'),
  };

  // --- Initialization ---

  async function init() {
    var data;
    try {
      var res = await fetch('/api/diff');
      data = await res.json();
      state.rawDiff = data.rawDiff || '';
      state.baseline = data.baseline || 'HEAD';
    } catch (err) {
      dom.loading.textContent = 'Failed to load diff data.';
      return;
    }

    state.git = data.git || {};
    updateHeaderInfo();

    if (!state.rawDiff.trim()) {
      dom.loading.classList.add('hidden');
      dom.emptyState.classList.remove('hidden');
      return;
    }

    state.files = Diff2Html.parse(state.rawDiff);
    state.rawFilePatches = splitDiffByFile(state.rawDiff);

    // Restore view mode from localStorage
    if (state.viewMode === 'side-by-side') {
      dom.btnSplit.classList.add('active');
      dom.btnUnified.classList.remove('active');
    }

    updateFileSummary();
    updateHeaderCommentCount();
    renderSidebar();
    renderDiffs();
    setupEventListeners();

    dom.loading.classList.add('hidden');
    startHeartbeat();
  }

  function updateHeaderInfo() {
    var git = state.git;
    dom.baselineInfo.textContent = '';

    if (git.branch) {
      var branchSpan = document.createElement('span');
      branchSpan.style.cssText = 'color:var(--accent-green);font-family:"JetBrains Mono",monospace;font-weight:500;';
      branchSpan.textContent = git.branch;
      dom.baselineInfo.appendChild(branchSpan);
    }

    if (git.baselineLabel) {
      var sep = document.createElement('span');
      sep.style.color = 'var(--text-muted)';
      sep.textContent = git.branch ? ' · ' : '';
      dom.baselineInfo.appendChild(sep);

      var labelSpan = document.createElement('span');
      labelSpan.textContent = git.baselineLabel;
      dom.baselineInfo.appendChild(labelSpan);
    }

    if (git.isGitButler) {
      var gbBadge = document.createElement('span');
      gbBadge.style.cssText = 'margin-left:8px;font-size:10px;padding:1px 6px;border-radius:4px;background:rgba(210,153,34,0.15);color:var(--accent-orange);border:1px solid rgba(210,153,34,0.3);font-family:"JetBrains Mono",monospace;';
      gbBadge.textContent = 'GB';
      dom.baselineInfo.appendChild(gbBadge);
    }
  }

  function updateFileSummary() {
    var totalAdd = 0, totalDel = 0;
    state.files.forEach(function (f) {
      totalAdd += f.addedLines;
      totalDel += f.deletedLines;
    });

    // Build summary with DOM methods
    dom.fileSummary.textContent = '';
    var countSpan = document.createElement('span');
    countSpan.textContent = state.files.length + ' file' + (state.files.length !== 1 ? 's' : '');
    var addSpan = document.createElement('span');
    addSpan.style.color = 'var(--accent-green)';
    addSpan.textContent = ' +' + totalAdd;
    var delSpan = document.createElement('span');
    delSpan.style.color = 'var(--accent-red)';
    delSpan.textContent = ' -' + totalDel;
    dom.fileSummary.appendChild(countSpan);
    dom.fileSummary.appendChild(addSpan);
    dom.fileSummary.appendChild(delSpan);
  }

  function updateHeaderCommentCount() {
    var count = state.comments.length;
    if (count > 0) {
      dom.headerCommentCount.textContent = count + ' comment' + (count !== 1 ? 's' : '');
      dom.headerCommentCount.classList.remove('hidden');
    } else {
      dom.headerCommentCount.classList.add('hidden');
    }
  }

  // --- Sidebar ---

  function renderSidebar() {
    dom.fileList.textContent = '';
    state.files.forEach(function (file, idx) {
      var li = document.createElement('li');
      li.className = 'file-item';
      li.dataset.index = idx;
      li.dataset.file = file.newName || file.oldName;

      var icon = document.createElement('span');
      icon.className = 'file-icon';
      var fileTypeIcon = getFileIcon(file.newName || file.oldName);
      if (file.isDeleted) {
        icon.classList.add('deleted');
        icon.textContent = fileTypeIcon || 'D';
      } else if (file.isNew) {
        icon.classList.add('added');
        icon.textContent = fileTypeIcon || 'A';
      } else if (file.isRename) {
        icon.classList.add('renamed');
        icon.textContent = fileTypeIcon || 'R';
      } else {
        icon.classList.add('modified');
        icon.textContent = fileTypeIcon || 'M';
      }

      var name = document.createElement('span');
      name.className = 'file-name';
      name.textContent = file.newName || file.oldName;
      name.title = file.newName || file.oldName;

      var stats = document.createElement('span');
      stats.className = 'file-stats';
      var addStat = document.createElement('span');
      addStat.className = 'stat-add';
      addStat.textContent = '+' + file.addedLines;
      var delStat = document.createElement('span');
      delStat.className = 'stat-del';
      delStat.textContent = ' -' + file.deletedLines;
      stats.appendChild(addStat);
      stats.appendChild(delStat);

      li.appendChild(icon);
      li.appendChild(name);
      li.appendChild(stats);

      li.addEventListener('click', function () {
        var section = document.getElementById('file-' + idx);
        if (section) section.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });

      dom.fileList.appendChild(li);
    });
  }

  function updateSidebarBadges() {
    var items = dom.fileList.querySelectorAll('.file-item');
    items.forEach(function (item) {
      var fileName = item.dataset.file;
      var count = state.comments.filter(function (c) { return c.file === fileName; }).length;
      var badge = item.querySelector('.comment-badge');
      if (count > 0) {
        if (!badge) {
          badge = document.createElement('span');
          badge.className = 'comment-badge';
          item.appendChild(badge);
        }
        badge.textContent = count;
      } else if (badge) {
        badge.remove();
      }
    });
  }

  // --- Diff Rendering ---

  function renderDiffs() {
    dom.diffs.textContent = '';

    state.files.forEach(function (file, idx) {
      var section = document.createElement('div');
      section.className = 'file-diff';
      section.id = 'file-' + idx;

      // Header
      var header = document.createElement('div');
      header.className = 'file-diff-header';

      var pathSpan = document.createElement('span');
      pathSpan.className = 'file-path';
      if (file.isRename) {
        pathSpan.textContent = file.oldName + ' → ' + file.newName;
      } else {
        pathSpan.textContent = file.newName || file.oldName;
      }

      var actions = document.createElement('div');
      actions.className = 'file-actions';

      // Diff stats bar
      var totalLines = file.addedLines + file.deletedLines;
      if (totalLines > 0) {
        var statsBar = document.createElement('div');
        statsBar.className = 'diff-stats-bar';
        var addBar = document.createElement('div');
        addBar.className = 'stat-bar-add';
        addBar.style.width = Math.round((file.addedLines / totalLines) * 100) + '%';
        var delBar = document.createElement('div');
        delBar.className = 'stat-bar-del';
        delBar.style.width = Math.round((file.deletedLines / totalLines) * 100) + '%';
        statsBar.appendChild(addBar);
        statsBar.appendChild(delBar);
        actions.appendChild(statsBar);
      }

      var commentBtn = document.createElement('button');
      commentBtn.className = 'file-comment-btn';
      commentBtn.textContent = 'Comment';
      commentBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        showFileCommentForm(section, file.newName || file.oldName);
      });

      var collapseBtn = document.createElement('button');
      collapseBtn.className = 'file-collapse-btn';
      collapseBtn.textContent = state.collapsedFiles[idx] ? '▶' : '▼';
      collapseBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        toggleFileCollapse(idx);
      });

      actions.appendChild(commentBtn);
      actions.appendChild(collapseBtn);
      header.appendChild(pathSpan);
      header.appendChild(actions);

      // Click header to toggle collapse
      header.style.cursor = 'pointer';
      header.addEventListener('click', function () {
        toggleFileCollapse(idx);
      });

      section.appendChild(header);

      // Render single file diff using diff2html. Pass the raw per-file slice
      // (preserving `diff --git`, rename metadata, mode changes, binary
      // markers) rather than a reconstructed --- / +++ / hunks patch, which
      // would lose all of that context and render renames as plain edits.
      var singleFileDiff = state.rawFilePatches[idx] || buildSingleFilePatch(file);
      var diffRendered = Diff2Html.html(singleFileDiff, {
        drawFileList: false,
        matching: 'lines',
        outputFormat: state.viewMode,
        renderNothingWhenEmpty: false,
        colorScheme: 'dark',
      });

      var diffBody = document.createElement('div');
      diffBody.className = 'file-diff-body';
      if (state.collapsedFiles[idx]) diffBody.classList.add('collapsed');
      // diff2html returns sanitized HTML from its own parser, safe to insert
      diffBody.insertAdjacentHTML('beforeend', diffRendered);
      applySyntaxHighlighting(diffBody, file.newName || file.oldName);
      section.appendChild(diffBody);

      // File-level comments container
      var fileLevelContainer = document.createElement('div');
      fileLevelContainer.className = 'file-level-comments';
      fileLevelContainer.id = 'file-comments-' + idx;
      fileLevelContainer.style.display = 'none';
      section.appendChild(fileLevelContainer);

      dom.diffs.appendChild(section);
    });

    attachLineClickHandlers();
    attachExpandHandlers();
    setupScrollSpy();
    reRenderAllComments();
  }

  // Split a raw git diff into per-file slices. Each slice begins with
  // `diff --git a/... b/...` and contains everything up to the next such line.
  // Preserves rename-from/rename-to, new-file-mode, deleted-file-mode, and
  // binary-diff markers that Diff2Html.parse+reconstruct would otherwise drop.
  function splitDiffByFile(rawDiff) {
    if (!rawDiff) return [];
    var lines = rawDiff.split('\n');
    var parts = [];
    var current = null;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.indexOf('diff --git ') === 0) {
        if (current !== null) parts.push(current.join('\n'));
        current = [line];
      } else if (current !== null) {
        current.push(line);
      }
    }
    if (current !== null) parts.push(current.join('\n'));
    return parts;
  }

  // Fallback used only if splitDiffByFile returns fewer entries than parsed
  // files (malformed diff without `diff --git` markers). Drops git metadata
  //, the current diff-from-git path shouldn't hit this.
  function buildSingleFilePatch(file) {
    var lines = [];
    var oldName = file.oldName || '/dev/null';
    var newName = file.newName || '/dev/null';
    lines.push('--- a/' + oldName);
    lines.push('+++ b/' + newName);
    file.blocks.forEach(function (block) {
      lines.push(block.header);
      block.lines.forEach(function (line) {
        lines.push(line.content);
      });
    });
    return lines.join('\n');
  }

  // --- Language Detection & Syntax Highlighting ---

  var EXT_LANG_MAP = {
    'js': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
    'ts': 'typescript', 'tsx': 'typescript', 'jsx': 'javascript',
    'py': 'python', 'go': 'go', 'rs': 'rust',
    'css': 'css', 'scss': 'scss', 'less': 'less',
    'html': 'xml', 'htm': 'xml', 'xml': 'xml', 'svg': 'xml',
    'json': 'json', 'yaml': 'yaml', 'yml': 'yaml', 'toml': 'ini',
    'java': 'java', 'kt': 'kotlin', 'scala': 'scala',
    'cpp': 'cpp', 'c': 'c', 'h': 'c', 'hpp': 'cpp',
    'cs': 'csharp', 'rb': 'ruby', 'php': 'php',
    'sh': 'bash', 'bash': 'bash', 'zsh': 'bash',
    'sql': 'sql', 'md': 'markdown', 'swift': 'swift',
    'r': 'r', 'lua': 'lua', 'vim': 'vim',
    'dockerfile': 'dockerfile', 'makefile': 'makefile',
  };

  var EXT_ICON_MAP = {
    'js': '⟨JS⟩', 'mjs': '⟨JS⟩', 'cjs': '⟨JS⟩', 'jsx': '⟨JSX⟩',
    'ts': '⟨TS⟩', 'tsx': '⟨TSX⟩',
    'py': '⟨PY⟩', 'go': '⟨GO⟩', 'rs': '⟨RS⟩',
    'css': '⟨CSS⟩', 'scss': '⟨CSS⟩', 'less': '⟨CSS⟩',
    'html': '⟨HTML⟩', 'htm': '⟨HTML⟩',
    'json': '⟨{ }⟩', 'yaml': '⟨YML⟩', 'yml': '⟨YML⟩', 'toml': '⟨CFG⟩',
    'java': '⟨JAVA⟩', 'kt': '⟨KT⟩',
    'cpp': '⟨C++⟩', 'c': '⟨C⟩', 'h': '⟨H⟩',
    'rb': '⟨RB⟩', 'php': '⟨PHP⟩', 'sh': '⟨SH⟩',
    'sql': '⟨SQL⟩', 'md': '⟨MD⟩', 'swift': '⟨SW⟩',
  };

  function getFileExt(filename) {
    if (!filename) return '';
    var base = filename.split('/').pop().toLowerCase();
    if (base === 'dockerfile') return 'dockerfile';
    if (base === 'makefile') return 'makefile';
    var parts = base.split('.');
    return parts.length > 1 ? parts.pop() : '';
  }

  function getLanguage(filename) {
    return EXT_LANG_MAP[getFileExt(filename)] || null;
  }

  function getFileIcon(filename) {
    return EXT_ICON_MAP[getFileExt(filename)] || null;
  }

  // Parse an hljs-produced HTML fragment (trusted: hljs escapes user text
  // and only emits <span class="hljs-*">...</span> wrappers) into DOM nodes
  // without touching innerHTML on user-facing elements.
  function hljsHtmlToFragment(html) {
    var range = document.createRange();
    return range.createContextualFragment(html);
  }

  function highlightNodeInPlace(node, lang) {
    var text = node.textContent;
    if (!text) return;
    try {
      var result = hljs.highlight(text, { language: lang, ignoreIllegals: true });
      while (node.firstChild) node.removeChild(node.firstChild);
      node.appendChild(hljsHtmlToFragment(result.value));
    } catch (e) {}
  }

  function applySyntaxHighlighting(diffBody, filename) {
    if (!window.hljs) return;
    var lang = getLanguage(filename);
    if (!lang) return;

    var codeLines = diffBody.querySelectorAll('.d2h-code-line-ctn');
    codeLines.forEach(function (el) {
      if (el.closest('.d2h-info')) return;

      // Walk the line's children. Text nodes get replaced with a highlighted
      // span fragment. <ins>/<del> elements have their inner text highlighted
      // in place, preserving the word-diff wrapper so CSS still styles them
      // (underline for adds, strikethrough for dels).
      //
      // Not perfect: a keyword split across an ins boundary won't be
      // recognized as a single token. But this is a strict improvement over
      // the previous behavior (skip the whole line if any ins/del is present).
      var children = Array.from(el.childNodes);
      children.forEach(function (node) {
        if (node.nodeType === Node.TEXT_NODE) {
          var text = node.textContent;
          if (!text) return;
          try {
            var result = hljs.highlight(text, { language: lang, ignoreIllegals: true });
            var span = document.createElement('span');
            span.appendChild(hljsHtmlToFragment(result.value));
            node.replaceWith(span);
          } catch (e) {}
        } else if (node.nodeType === Node.ELEMENT_NODE) {
          var tag = node.tagName;
          if (tag === 'INS' || tag === 'DEL') {
            highlightNodeInPlace(node, lang);
          }
        }
      });
    });
  }

  // --- Markdown in Comments ---

  function renderMarkdown(text) {
    // Simple inline markdown: **bold**, *italic*, `code`, newlines
    var escaped = text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');

    return escaped
      .replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\*([^*]+)\*/g, '<em>$1</em>')
      .replace(/\n/g, '<br>');
  }

  // --- Expand Context ---

  function attachExpandHandlers() {
    var hunkHeaders = document.querySelectorAll('.d2h-info');
    hunkHeaders.forEach(function (row) {
      var ctn = row.querySelector('.d2h-code-line-ctn');
      if (!ctn) return;

      // Parse @@ -a,b +c,d @@ from hunk header
      var headerText = ctn.textContent.trim();
      var match = headerText.match(/@@ -(\d+),?\d* \+(\d+),?\d* @@/);
      if (!match) return;

      var newStart = parseInt(match[2], 10);

      // Make the hunk header clickable
      var expandBtn = document.createElement('span');
      expandBtn.className = 'expand-context-btn';
      expandBtn.textContent = '↕ Expand';
      expandBtn.title = 'Show surrounding context';
      ctn.appendChild(expandBtn);

      expandBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        var fileSection = row.closest('.file-diff');
        if (!fileSection) return;
        var fileIdx = parseInt(fileSection.id.replace('file-', ''), 10);
        var file = state.files[fileIdx];
        var fileName = file.newName || file.oldName;

        // Fetch 10 lines before the hunk start
        var fetchStart = Math.max(1, newStart - 10);
        var fetchEnd = newStart - 1;
        if (fetchEnd < fetchStart) return;

        fetch('/api/file-context?file=' + encodeURIComponent(fileName) + '&start=' + fetchStart + '&end=' + fetchEnd)
          .then(function (r) { return r.json(); })
          .then(function (data) {
            if (!data.lines || data.lines.length === 0) return;
            var tbody = row.closest('tbody') || row.closest('table');
            if (!tbody) return;

            data.lines.forEach(function (line, i) {
              var tr = document.createElement('tr');
              var tdNum = document.createElement('td');
              tdNum.className = 'd2h-code-linenumber';
              tdNum.style.cssText = 'opacity:0.5;';
              var num1 = document.createElement('div');
              num1.className = 'line-num1';
              num1.textContent = fetchStart + i;
              var num2 = document.createElement('div');
              num2.className = 'line-num2';
              num2.textContent = fetchStart + i;
              tdNum.appendChild(num1);
              tdNum.appendChild(num2);

              var tdCode = document.createElement('td');
              tdCode.className = 'd2h-code-line-ctn';
              tdCode.style.cssText = 'opacity:0.5;padding-left:1em;';
              tdCode.textContent = ' ' + line;

              tr.appendChild(tdNum);
              tr.appendChild(tdCode);
              row.parentNode.insertBefore(tr, row.nextSibling);
            });

            expandBtn.remove();
          })
          .catch(function () {});
      });
    });
  }

  // --- File Collapse ---

  function toggleFileCollapse(idx) {
    state.collapsedFiles[idx] = !state.collapsedFiles[idx];
    var section = document.getElementById('file-' + idx);
    if (!section) return;
    var body = section.querySelector('.file-diff-body');
    var btn = section.querySelector('.file-collapse-btn');
    if (body) body.classList.toggle('collapsed', state.collapsedFiles[idx]);
    if (btn) btn.textContent = state.collapsedFiles[idx] ? '▶' : '▼';
  }

  // --- Inline Comment System ---

  function attachLineClickHandlers() {
    var lineNumbers = document.querySelectorAll('.d2h-code-linenumber, .d2h-code-side-linenumber');
    lineNumbers.forEach(function (ln) {
      ln.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();

        var row = ln.closest('tr');
        if (!row) return;

        var fileSection = ln.closest('.file-diff');
        if (!fileSection) return;

        var fileIdx = parseInt(fileSection.id.replace('file-', ''), 10);
        var file = state.files[fileIdx];
        var fileName = file.newName || file.oldName;
        var lineNum = extractLineNumber(ln);

        // Don't open another form if one is already there
        if (row.nextElementSibling && row.nextElementSibling.classList.contains('comment-form-row')) {
          return;
        }

        insertCommentForm(row, fileName, lineNum);
      });
    });
  }

  function extractLineNumber(lineNumberEl) {
    var text = lineNumberEl.textContent.trim();
    var nums = text.split(/\s+/).filter(function (n) { return n && !isNaN(n); });
    if (nums.length > 0) {
      return parseInt(nums[nums.length - 1], 10);
    }
    return null;
  }

  function insertCommentForm(afterRow, fileName, lineNum) {
    var formRow = document.createElement('tr');
    formRow.className = 'comment-form-row';

    var td = document.createElement('td');
    td.colSpan = 20;

    var formDiv = document.createElement('div');
    formDiv.className = 'comment-form';

    var textarea = document.createElement('textarea');
    textarea.placeholder = 'Leave a comment on line ' + (lineNum || '?') + '...';

    var actionsDiv = document.createElement('div');
    actionsDiv.className = 'form-actions';

    var cancelBtn = document.createElement('button');
    cancelBtn.className = 'btn-cancel';
    cancelBtn.textContent = 'Cancel';

    var submitBtn = document.createElement('button');
    submitBtn.className = 'btn-submit';
    submitBtn.textContent = 'Add Comment';

    actionsDiv.appendChild(cancelBtn);
    actionsDiv.appendChild(submitBtn);
    formDiv.appendChild(textarea);
    formDiv.appendChild(actionsDiv);
    td.appendChild(formDiv);
    formRow.appendChild(td);

    afterRow.after(formRow);
    textarea.focus();

    cancelBtn.addEventListener('click', function () { formRow.remove(); });
    submitBtn.addEventListener('click', function () {
      var body = textarea.value.trim();
      if (!body) return;
      addComment({ file: fileName, line: lineNum, body: body, type: 'inline' });
      formRow.remove();
    });

    textarea.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
        submitBtn.click();
      }
      if (e.key === 'Escape') {
        formRow.remove();
      }
    });
  }

  function showFileCommentForm(fileSection, fileName) {
    var idx = fileSection.id.replace('file-', '');
    var container = document.getElementById('file-comments-' + idx);
    container.style.display = 'block';

    if (container.querySelector('.comment-form')) return;

    var formDiv = document.createElement('div');
    formDiv.className = 'comment-form';

    var textarea = document.createElement('textarea');
    textarea.placeholder = 'Leave a comment on this file...';

    var actionsDiv = document.createElement('div');
    actionsDiv.className = 'form-actions';

    var cancelBtn = document.createElement('button');
    cancelBtn.className = 'btn-cancel';
    cancelBtn.textContent = 'Cancel';

    var submitBtn = document.createElement('button');
    submitBtn.className = 'btn-submit';
    submitBtn.textContent = 'Add Comment';

    actionsDiv.appendChild(cancelBtn);
    actionsDiv.appendChild(submitBtn);
    formDiv.appendChild(textarea);
    formDiv.appendChild(actionsDiv);
    container.appendChild(formDiv);
    textarea.focus();

    cancelBtn.addEventListener('click', function () {
      formDiv.remove();
      if (!container.querySelector('.file-level-comment')) {
        container.style.display = 'none';
      }
    });

    submitBtn.addEventListener('click', function () {
      var body = textarea.value.trim();
      if (!body) return;
      addComment({ file: fileName, line: null, body: body, type: 'file-level' });
      formDiv.remove();
    });

    textarea.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
        submitBtn.click();
      }
      if (e.key === 'Escape') {
        cancelBtn.click();
      }
    });
  }

  // --- Comment Management ---

  function addComment(comment) {
    comment.id = 'c' + (++commentIdCounter);
    state.comments.push(comment);
    updateSidebarBadges();
    updateHeaderCommentCount();
    reRenderAllComments();
  }

  function removeComment(id) {
    state.comments = state.comments.filter(function (c) { return c.id !== id; });
    updateSidebarBadges();
    updateHeaderCommentCount();
    reRenderAllComments();
  }

  function reRenderAllComments() {
    // Clear existing rendered comments
    document.querySelectorAll('.inline-comment').forEach(function (el) { el.remove(); });
    document.querySelectorAll('.inline-comment-row').forEach(function (el) { el.remove(); });

    // Render inline comments
    state.comments.filter(function (c) { return c.type === 'inline'; }).forEach(function (comment) {
      renderInlineComment(comment);
    });

    // Render file-level comments
    state.files.forEach(function (file, idx) {
      var fileName = file.newName || file.oldName;
      var fileComments = state.comments.filter(function (c) {
        return c.file === fileName && c.type === 'file-level';
      });
      var container = document.getElementById('file-comments-' + idx);
      if (!container) return;

      container.querySelectorAll('.file-level-comment').forEach(function (el) { el.remove(); });

      if (fileComments.length > 0) {
        container.style.display = 'block';
        fileComments.forEach(function (comment) {
          var el = createCommentElement(comment);
          el.classList.add('file-level-comment');
          var form = container.querySelector('.comment-form');
          if (form) {
            container.insertBefore(el, form);
          } else {
            container.appendChild(el);
          }
        });
      } else if (!container.querySelector('.comment-form')) {
        container.style.display = 'none';
      }
    });
  }

  function renderInlineComment(comment) {
    var fileIdx = state.files.findIndex(function (f) {
      return (f.newName || f.oldName) === comment.file;
    });
    if (fileIdx === -1) return;

    var fileSection = document.getElementById('file-' + fileIdx);
    if (!fileSection) return;

    var lineNumbers = fileSection.querySelectorAll('.d2h-code-linenumber, .d2h-code-side-linenumber');
    var targetRow = null;

    for (var i = 0; i < lineNumbers.length; i++) {
      var num = extractLineNumber(lineNumbers[i]);
      if (num === comment.line) {
        targetRow = lineNumbers[i].closest('tr');
        break;
      }
    }

    if (!targetRow) return;

    var commentEl = createCommentElement(comment);
    var commentRow = document.createElement('tr');
    commentRow.className = 'inline-comment-row';
    var td = document.createElement('td');
    td.colSpan = 20;
    td.appendChild(commentEl);
    commentRow.appendChild(td);

    targetRow.after(commentRow);
  }

  function createCommentElement(comment) {
    var el = document.createElement('div');
    el.className = 'inline-comment';
    el.dataset.commentId = comment.id;

    var location = comment.type === 'inline'
      ? 'Line ' + comment.line
      : 'File comment';

    // Build with DOM methods
    var headerDiv = document.createElement('div');
    headerDiv.className = 'comment-header';

    var locationSpan = document.createElement('span');
    locationSpan.textContent = location;
    headerDiv.appendChild(locationSpan);

    var actionsDiv = document.createElement('div');
    actionsDiv.className = 'comment-actions';

    var editBtn = document.createElement('button');
    editBtn.className = 'btn-edit';
    editBtn.title = 'Edit';
    editBtn.textContent = 'Edit';

    var deleteBtn = document.createElement('button');
    deleteBtn.className = 'btn-delete';
    deleteBtn.title = 'Delete';
    deleteBtn.textContent = 'Delete';

    actionsDiv.appendChild(editBtn);
    actionsDiv.appendChild(deleteBtn);
    headerDiv.appendChild(actionsDiv);

    var bodyDiv = document.createElement('div');
    bodyDiv.className = 'comment-body';
    // Render with simple markdown support
    bodyDiv.insertAdjacentHTML('beforeend', renderMarkdown(comment.body));

    el.appendChild(headerDiv);
    el.appendChild(bodyDiv);

    deleteBtn.addEventListener('click', function () {
      removeComment(comment.id);
    });

    editBtn.addEventListener('click', function () {
      bodyDiv.textContent = '';

      var textarea = document.createElement('textarea');
      textarea.style.cssText = 'width:100%;min-height:40px;background:var(--bg-primary);color:var(--text-primary);border:1px solid var(--border);border-radius:4px;padding:4px 8px;font-size:13px;font-family:inherit;';
      textarea.value = comment.body;

      var btnRow = document.createElement('div');
      btnRow.style.cssText = 'display:flex;justify-content:flex-end;gap:8px;margin-top:4px;';

      var saveBtn = document.createElement('button');
      saveBtn.textContent = 'Save';
      saveBtn.style.cssText = 'padding:2px 8px;border-radius:4px;font-size:11px;cursor:pointer;background:var(--accent-green);color:#fff;border:none;';

      var cancelEditBtn = document.createElement('button');
      cancelEditBtn.textContent = 'Cancel';
      cancelEditBtn.style.cssText = 'padding:2px 8px;border-radius:4px;font-size:11px;cursor:pointer;background:var(--bg-tertiary);color:var(--text-secondary);border:1px solid var(--border);';

      btnRow.appendChild(saveBtn);
      btnRow.appendChild(cancelEditBtn);
      bodyDiv.appendChild(textarea);
      bodyDiv.appendChild(btnRow);
      textarea.focus();

      saveBtn.addEventListener('click', function () {
        var newBody = textarea.value.trim();
        if (newBody) {
          comment.body = newBody;
          reRenderAllComments();
        }
      });

      cancelEditBtn.addEventListener('click', function () {
        reRenderAllComments();
      });
    });

    return el;
  }

  // --- Scroll Spy ---

  function setupScrollSpy() {
    var fileSections = document.querySelectorAll('.file-diff');
    if (fileSections.length === 0) return;

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          var idx = entry.target.id.replace('file-', '');
          state.focusedFileIdx = parseInt(idx, 10);
          var items = dom.fileList.querySelectorAll('.file-item');
          items.forEach(function (item) { item.classList.remove('active'); });
          var activeItem = dom.fileList.querySelector('.file-item[data-index="' + idx + '"]');
          if (activeItem) activeItem.classList.add('active');
        }
      });
    }, {
      rootMargin: '-66px 0px -60% 0px',
      threshold: 0,
    });

    fileSections.forEach(function (section) { observer.observe(section); });
  }

  // --- Event Listeners ---

  function setupEventListeners() {
    dom.btnUnified.addEventListener('click', function () {
      if (state.viewMode === 'line-by-line') return;
      state.viewMode = 'line-by-line';
      localStorage.setItem('ds-view-mode', state.viewMode);
      dom.btnUnified.classList.add('active');
      dom.btnSplit.classList.remove('active');
      renderDiffs();
    });

    dom.btnSplit.addEventListener('click', function () {
      if (state.viewMode === 'side-by-side') return;
      state.viewMode = 'side-by-side';
      localStorage.setItem('ds-view-mode', state.viewMode);
      dom.btnSplit.classList.add('active');
      dom.btnUnified.classList.remove('active');
      renderDiffs();
    });

    var manualSidebarToggle = false;

    function setSidebarCollapsed(collapsed) {
      dom.sidebar.classList.toggle('collapsed', collapsed);
      dom.diffContainer.classList.toggle('expanded', collapsed);
      dom.btnToggleSidebar.classList.toggle('collapsed', collapsed);
      dom.btnToggleSidebar.textContent = collapsed ? '▶' : '◀';
    }

    dom.btnToggleSidebar.addEventListener('click', function () {
      manualSidebarToggle = true;
      var collapsed = !dom.sidebar.classList.contains('collapsed');
      setSidebarCollapsed(collapsed);
    });

    function checkSidebarFit() {
      if (manualSidebarToggle) return;
      var sidebarWidth = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--sidebar-width'), 10);
      var shouldCollapse = sidebarWidth > window.innerWidth * 0.30;
      setSidebarCollapsed(shouldCollapse);
    }

    checkSidebarFit();
    window.addEventListener('resize', function () {
      manualSidebarToggle = false;
      checkSidebarFit();
    });

    dom.btnApprove.addEventListener('click', function () { showReviewModal('approve'); });
    dom.btnRequestChanges.addEventListener('click', function () { showReviewModal('request-changes'); });

    dom.modalCancel.addEventListener('click', hideReviewModal);
    document.querySelector('#review-modal .modal-backdrop').addEventListener('click', hideReviewModal);

    dom.modalApprove.addEventListener('click', function () { submitReview('approve'); });
    dom.modalRequestChanges.addEventListener('click', function () { submitReview('request-changes'); });

    // --- File search ---
    dom.fileSearch.addEventListener('input', function () {
      var query = dom.fileSearch.value.toLowerCase();
      var items = dom.fileList.querySelectorAll('.file-item');
      items.forEach(function (item) {
        var fileName = (item.dataset.file || '').toLowerCase();
        item.style.display = fileName.indexOf(query) !== -1 ? '' : 'none';
      });
    });

    // --- Keyboard shortcuts ---
    document.addEventListener('keydown', function (e) {
      // Escape always works, even in inputs
      // Escape to close modals
      if (e.key === 'Escape') {
        if (!dom.submittedOverlay.classList.contains('hidden')) {
          dom.submittedOverlay.classList.add('hidden');
          return;
        }
        if (!dom.reviewModal.classList.contains('hidden')) {
          hideReviewModal();
          return;
        }
        // Close any open comment forms
        var openForm = document.querySelector('.comment-form-row');
        if (openForm) {
          openForm.remove();
          return;
        }
        return;
      }

      // Don't trigger other shortcuts when typing in an input/textarea
      var tag = e.target.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;

      // j/k to navigate files
      if (e.key === 'j') {
        e.preventDefault();
        navigateFile(1);
        return;
      }
      if (e.key === 'k') {
        e.preventDefault();
        navigateFile(-1);
        return;
      }

      // a to approve
      if (e.key === 'a' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        showReviewModal('approve');
        return;
      }

      // x to request changes
      if (e.key === 'x' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        showReviewModal('request-changes');
        return;
      }

      // / to focus search
      if (e.key === '/') {
        e.preventDefault();
        dom.fileSearch.focus();
        return;
      }

      // e to collapse/expand focused file
      if (e.key === 'e') {
        e.preventDefault();
        toggleFileCollapse(state.focusedFileIdx);
        return;
      }
    });
  }

  function navigateFile(direction) {
    var newIdx = state.focusedFileIdx + direction;
    if (newIdx < 0) newIdx = 0;
    if (newIdx >= state.files.length) newIdx = state.files.length - 1;
    state.focusedFileIdx = newIdx;
    var section = document.getElementById('file-' + newIdx);
    if (section) section.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  // --- Review Modal ---

  function showReviewModal(decision) {
    dom.reviewModal.classList.remove('hidden');
    dom.reviewSummary.value = '';

    if (decision === 'approve') {
      dom.modalTitle.textContent = 'Approve Changes';
      dom.modalApprove.classList.remove('hidden');
      dom.modalRequestChanges.classList.add('hidden');
    } else {
      dom.modalTitle.textContent = 'Request Changes';
      dom.modalApprove.classList.add('hidden');
      dom.modalRequestChanges.classList.remove('hidden');
    }

    // Render comment summary using DOM methods
    dom.commentSummaryEl.textContent = '';
    if (state.comments.length > 0) {
      state.comments.forEach(function (c) {
        var div = document.createElement('div');
        div.className = 'comment-preview';

        var locationDiv = document.createElement('div');
        locationDiv.className = 'comment-location';
        locationDiv.textContent = c.type === 'inline'
          ? c.file + ':' + c.line
          : c.file + ' (file)';

        var textDiv = document.createElement('div');
        textDiv.className = 'comment-text';
        textDiv.textContent = c.body;

        div.appendChild(locationDiv);
        div.appendChild(textDiv);
        dom.commentSummaryEl.appendChild(div);
      });
    } else {
      var emptyMsg = document.createElement('p');
      emptyMsg.style.cssText = 'color:var(--text-muted);font-size:12px;';
      emptyMsg.textContent = 'No comments added.';
      dom.commentSummaryEl.appendChild(emptyMsg);
    }

    dom.reviewSummary.focus();
  }

  function hideReviewModal() {
    dom.reviewModal.classList.add('hidden');
  }

  async function submitReview(decision) {
    var review = {
      decision: decision,
      summary: dom.reviewSummary.value.trim() || null,
      comments: state.comments.map(function (c) {
        return { id: c.id, file: c.file, line: c.line, body: c.body, type: c.type };
      }),
    };

    try {
      var res = await fetch('/api/review', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(review),
      });

      if (!res.ok) throw new Error('Failed to submit review');

      state.submitted = true;
      stopHeartbeat();
      hideReviewModal();

      dom.submittedText.textContent = decision === 'approve'
        ? 'Changes approved.'
        : 'Changes requested with ' + state.comments.length + ' comment' + (state.comments.length !== 1 ? 's' : '') + '.';
      dom.submittedOverlay.classList.remove('hidden');

    } catch (err) {
      alert('Failed to submit review: ' + err.message);
    }
  }

  // --- Start ---
  init();
})();
