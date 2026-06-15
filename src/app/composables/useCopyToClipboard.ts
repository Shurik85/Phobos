type TextSource = string | (() => string | Promise<string>);

function legacyCopy(text: string): boolean {
  const activeElement =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;

  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.top = '0';
  ta.style.left = '0';
  ta.style.width = '1px';
  ta.style.height = '1px';
  ta.style.padding = '0';
  ta.style.margin = '0';
  ta.style.border = 'none';
  ta.style.outline = 'none';
  ta.style.boxShadow = 'none';
  ta.style.background = 'transparent';
  ta.style.opacity = '0';
  ta.style.pointerEvents = 'none';
  ta.style.zIndex = '-1';

  const host =
    activeElement?.closest('[role="dialog"]') ??
    document.fullscreenElement ??
    document.body;
  host.appendChild(ta);

  let ok = false;
  try {
    ta.focus({ preventScroll: true });
    ta.setSelectionRange(0, ta.value.length);
    ok = document.execCommand('copy');
  } catch {
    ok = false;
  } finally {
    host.removeChild(ta);
    activeElement?.focus({ preventScroll: true });
  }
  return ok;
}

function isSecureClipboardAvailable(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.isSecureContext &&
    !!navigator.clipboard?.writeText
  );
}

function supportsAsyncClipboardItem(): boolean {
  if (typeof window === 'undefined' || !window.isSecureContext) {
    return false;
  }
  if (typeof ClipboardItem === 'undefined' || !navigator.clipboard?.write) {
    return false;
  }
  try {
    new ClipboardItem({
      'text/plain': Promise.resolve(new Blob([''], { type: 'text/plain' })),
    });
    return true;
  } catch {
    return false;
  }
}

function assertCopyable(text: unknown): asserts text is string {
  if (typeof text !== 'string' || text.length === 0) {
    throw new Error('Nothing to copy');
  }
}

async function writeResolvedText(text: string): Promise<void> {
  if (isSecureClipboardAvailable()) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      void 0;
    }
  }
  if (!legacyCopy(text)) {
    throw new Error('Clipboard copy failed');
  }
}

export function useCopyToClipboard() {
  return async (source: TextSource): Promise<void> => {
    if (typeof source === 'string') {
      assertCopyable(source);
      await writeResolvedText(source);
      return;
    }

    let textPromise: Promise<string> | undefined;
    const resolveText = (): Promise<string> => {
      if (!textPromise) {
        textPromise = Promise.resolve(source()).then((text) => {
          assertCopyable(text);
          return text;
        });
      }
      return textPromise;
    };

    if (supportsAsyncClipboardItem()) {
      try {
        await navigator.clipboard.write([
          new ClipboardItem({
            'text/plain': resolveText().then(
              (text) => new Blob([text], { type: 'text/plain' })
            ),
          }),
        ]);
        return;
      } catch {
        void 0;
      }
    }

    await writeResolvedText(await resolveText());
  };
}
