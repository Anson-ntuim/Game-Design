// Browser local file pick only (no upload to a server).
// itch.io embeds the game in a cross-origin iframe; programmatic input.click()
// from the Godot→JS bridge often loses "user activation" and the dialog never
// opens. Fix: show a real HTML overlay the player clicks / drops onto.
//
// Use a global `var` (not only window.X inside an IIFE) so Godot's
// JavaScriptBridge.get_interface("JumpMusicPicker") can find it after eval.
var JumpMusicPicker = {
  _generation: 0,
  _overlay: null,
  _input: null,

  report: function (message) {
    var status = document.getElementById('jump-music-status');
    if (!status) {
      status = document.createElement('div');
      status.id = 'jump-music-status';
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      status.style.cssText =
        'position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);';
      document.body.appendChild(status);
    }
    if (status.textContent !== message) status.textContent = message;
  },

  cancel: function () {
    this._generation += 1;
    if (this._overlay) {
      this._overlay.remove();
      this._overlay = null;
    }
    if (this._input) {
      this._input.remove();
      this._input = null;
    }
  },

  open: function (callback) {
    var self = this;
    var ACCEPT = '.wav,.mp3,.ogg,audio/wav,audio/mpeg,audio/ogg';
    var MAX_BYTES = 32 * 1024 * 1024;
    this.cancel();
    var token = this._generation;

    function finish(name, buffer, error) {
      if (token !== self._generation) return;
      self.cancel();
      if (typeof callback === 'function') callback(name, buffer, error);
    }

    function readFile(file) {
      if (!file) return finish('', null, '');
      if (file.size > MAX_BYTES) return finish('', null, '請選擇 32 MB 以內的音樂');
      var name = String(file.name || 'music');
      var lower = name.toLowerCase();
      if (!/\.(wav|mp3|ogg)$/.test(lower) && !(file.type || '').startsWith('audio/')) {
        return finish('', null, '請選擇 WAV、MP3 或 OGG');
      }
      file
        .arrayBuffer()
        .then(function (buf) {
          finish(name, buf, '');
        })
        .catch(function () {
          finish('', null, '瀏覽器無法讀取這個檔案，請重新選擇');
        });
    }

    var picker = document.createElement('input');
    picker.type = 'file';
    picker.accept = ACCEPT;
    picker.setAttribute('aria-label', '選擇音樂檔');
    picker.style.cssText =
      'position:fixed;left:-10000px;top:0;width:1px;height:1px;opacity:0;';
    document.body.appendChild(picker);
    this._input = picker;

    picker.addEventListener('cancel', function () {
      finish('', null, '');
    }, { once: true });
    picker.addEventListener(
      'change',
      function () {
        var file = picker.files && picker.files[0];
        readFile(file);
      },
      { once: true }
    );

    var layer = document.createElement('div');
    layer.id = 'jump-music-picker-overlay';
    layer.setAttribute('role', 'dialog');
    layer.setAttribute('aria-modal', 'true');
    layer.setAttribute('aria-label', '選擇音樂');
    layer.style.cssText = [
      'position:fixed',
      'inset:0',
      'z-index:2147483646',
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'background:rgba(6,8,18,0.72)',
      'font-family:system-ui,-apple-system,sans-serif',
      'color:#f4f6ff',
      'backdrop-filter:blur(2px)',
    ].join(';');

    var card = document.createElement('div');
    card.style.cssText = [
      'width:min(440px,92vw)',
      'padding:28px 24px',
      'border-radius:16px',
      'background:#0c1224',
      'border:1px solid rgba(168,212,255,0.55)',
      'box-shadow:0 18px 48px rgba(0,0,0,0.45)',
      'text-align:center',
    ].join(';');

    var title = document.createElement('div');
    title.textContent = '選擇音樂';
    title.style.cssText = 'font-size:22px;font-weight:700;margin-bottom:8px;';

    var hint = document.createElement('div');
    hint.textContent = 'WAV／MP3／OGG，32 MB 以內。也可把檔案拖進這裡。';
    hint.style.cssText = 'font-size:14px;opacity:0.72;line-height:1.45;margin-bottom:20px;';

    var pickBtn = document.createElement('button');
    pickBtn.type = 'button';
    pickBtn.textContent = '從裝置選擇檔案';
    pickBtn.style.cssText = [
      'display:block',
      'width:100%',
      'padding:14px 16px',
      'margin:0 0 10px 0',
      'border:0',
      'border-radius:10px',
      'background:#a8d4ff',
      'color:#0a1020',
      'font-size:16px',
      'font-weight:700',
      'cursor:pointer',
    ].join(';');

    var cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.textContent = '取消';
    cancelBtn.style.cssText = [
      'display:block',
      'width:100%',
      'padding:12px 16px',
      'border:1px solid rgba(255,255,255,0.18)',
      'border-radius:10px',
      'background:transparent',
      'color:#f4f6ff',
      'font-size:15px',
      'cursor:pointer',
    ].join(';');

    var dropHint = document.createElement('div');
    dropHint.textContent = '拖放區域';
    dropHint.style.cssText =
      'margin-top:16px;padding:18px;border:1.5px dashed rgba(168,212,255,0.45);border-radius:12px;font-size:13px;opacity:0.8;';

    pickBtn.addEventListener('click', function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      picker.click();
    });
    cancelBtn.addEventListener('click', function (ev) {
      ev.preventDefault();
      finish('', null, '');
    });
    layer.addEventListener('click', function (ev) {
      if (ev.target === layer) finish('', null, '');
    });

    function onDrag(ev) {
      ev.preventDefault();
      ev.stopPropagation();
      dropHint.style.borderColor = 'rgba(168,212,255,0.95)';
      dropHint.style.background = 'rgba(168,212,255,0.08)';
    }
    function onDragLeave(ev) {
      ev.preventDefault();
      dropHint.style.borderColor = 'rgba(168,212,255,0.45)';
      dropHint.style.background = 'transparent';
    }
    function onDrop(ev) {
      ev.preventDefault();
      ev.stopPropagation();
      onDragLeave(ev);
      var file = ev.dataTransfer && ev.dataTransfer.files && ev.dataTransfer.files[0];
      readFile(file);
    }
    [layer, card, dropHint].forEach(function (el) {
      el.addEventListener('dragenter', onDrag);
      el.addEventListener('dragover', onDrag);
      el.addEventListener('dragleave', onDragLeave);
      el.addEventListener('drop', onDrop);
    });

    window.addEventListener(
      'keydown',
      function (ev) {
        if (ev.key === 'Escape') finish('', null, '');
      },
      { once: true }
    );

    card.appendChild(title);
    card.appendChild(hint);
    card.appendChild(pickBtn);
    card.appendChild(cancelBtn);
    card.appendChild(dropHint);
    layer.appendChild(card);
    document.body.appendChild(layer);
    this._overlay = layer;
    pickBtn.focus();
    this.report('請在彈出層選擇或拖入音樂檔');
  },
};
window.JumpMusicPicker = JumpMusicPicker;
