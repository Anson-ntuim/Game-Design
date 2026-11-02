// Browser file input only: no network request or server upload.
(() => {
  let generation = 0;
  let input = null;
  window.JumpMusicPicker = {
    report(message) {
      // Canvas 內的狀態也提供給瀏覽器輔助技術。
      let status = document.getElementById('jump-music-status');
      if (!status) {
        status = document.createElement('div');
        status.id = 'jump-music-status';
        status.setAttribute('role', 'status');
        status.setAttribute('aria-live', 'polite');
        status.style.cssText = 'position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);';
        document.body.appendChild(status);
      }
      if (status.textContent !== message) status.textContent = message;
    },
    cancel() {
      generation++;
      if (input) input.remove();
      input = null;
    },
    open(callback) {
      this.cancel();
      const token = generation;
      const picker = document.createElement('input');
      picker.type = 'file';
      picker.accept = '.wav,.mp3,.ogg,audio/wav,audio/mpeg,audio/ogg';
      picker.style.display = 'none';
      document.body.appendChild(picker);
      input = picker;
      const finish = (name, buffer, error) => {
        if (token !== generation) return;
        picker.remove();
        input = null;
        callback(name, buffer, error);
      };
      picker.addEventListener('cancel', () => finish('', null, ''), { once: true });
      picker.addEventListener('change', async () => {
        const file = picker.files[0];
        if (!file) return finish('', null, '');
        if (file.size > 32 * 1024 * 1024) return finish('', null, '請選擇 32 MB 以內的音樂');
        try {
          finish(file.name, await file.arrayBuffer(), '');
        } catch (_) {
          finish('', null, '瀏覽器無法讀取這個檔案，請重新選擇');
        }
      }, { once: true });
      picker.click();
    }
  };
})();
