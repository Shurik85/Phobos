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

export function useCopyToClipboard() {
  return async (source: TextSource): Promise<void> => {
    if (typeof source === 'string') {
      if (source.length === 0) {
        throw new Error('Nothing to copy');
      }

      if (isSecureClipboardAvailable()) {
        try {
          await navigator.clipboard.writeText(source);
          return;
        } catch {
          // fall through to legacy below
        }
      }

      if (!legacyCopy(source)) {
        throw new Error('Clipboard copy failed');
      }
      return;
    }

    const text = await source();
    if (typeof text !== 'string' || text.length === 0) {
      throw new Error('Nothing to copy');
    }

    if (isSecureClipboardAvailable()) {
      try {
        await navigator.clipboard.writeText(text);
        return;
      } catch {
        // user gesture is already consumed by the await on the source;
        // legacyCopy will likely fail here, but try anyway.
      }
    }

    if (!legacyCopy(text)) {
      throw new Error('Clipboard copy failed');
    }
  };
}
