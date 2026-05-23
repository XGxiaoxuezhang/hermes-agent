import { useState, useRef, useEffect, useCallback } from "react";
import { createPortal } from "react-dom";
import { Button } from "@nous-research/ui/ui/components/button";
import { Typography } from "@/components/NouiTypography";
import { useI18n } from "@/i18n/context";
import { LOCALE_META } from "@/i18n";
import type { Locale } from "@/i18n";

/**
 * Language picker — shows the current language name, opens a dropdown of all
 * supported locales when clicked. Persists choice to localStorage via the
 * I18n context.
 */
export function LanguageSwitcher({ dropUp = false }: LanguageSwitcherProps) {
  const { locale, setLocale, t } = useI18n();
  const [open, setOpen] = useState(false);
  const [menuStyle, setMenuStyle] = useState<React.CSSProperties | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const [portalRoot] = useState<HTMLElement | null>(() =>
    typeof document !== "undefined" ? document.body : null,
  );

  const updateMenuPosition = useCallback(() => {
    const trigger = containerRef.current;
    if (!trigger || typeof window === "undefined") return;

    const rect = trigger.getBoundingClientRect();
    const gap = 6;
    setMenuStyle({
      position: "fixed",
      right: Math.max(8, window.innerWidth - rect.right),
      ...(dropUp
        ? { bottom: Math.max(8, window.innerHeight - rect.top + gap) }
        : { top: Math.min(window.innerHeight - 8, rect.bottom + gap) }),
    });
  }, [dropUp]);

  useEffect(() => {
    if (!open) return;
    updateMenuPosition();
    window.addEventListener("resize", updateMenuPosition);
    window.visualViewport?.addEventListener("resize", updateMenuPosition);
    return () => {
      window.removeEventListener("resize", updateMenuPosition);
      window.visualViewport?.removeEventListener("resize", updateMenuPosition);
    };
  }, [open, updateMenuPosition]);

  // Close on outside click / Escape so the dropdown doesn't trap the user.
  useEffect(() => {
    if (!open) return;

    function onPointerDown(e: PointerEvent) {
      const target = e.target as Node;
      if (
        !containerRef.current?.contains(target) &&
        !menuRef.current?.contains(target)
      ) {
        setOpen(false);
      }
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }

    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const current = LOCALE_META[locale];
  const allLocales = Object.entries(LOCALE_META) as Array<[Locale, typeof current]>;
  const menu =
    open && portalRoot && menuStyle
      ? createPortal(
          <div
            ref={menuRef}
            role="listbox"
            aria-label={t.language.switchTo}
            className="z-[100] min-w-[10rem] rounded-md border border-border bg-popover shadow-xl py-1 max-h-80 overflow-y-auto"
            style={menuStyle}
          >
            {allLocales.map(([code, meta]) => {
              const selected = code === locale;
              return (
                <button
                  key={code}
                  role="option"
                  aria-selected={selected}
                  onClick={() => {
                    setLocale(code);
                    setOpen(false);
                  }}
                  className={
                    "w-full text-left px-3 py-1.5 text-xs flex items-center gap-2 hover:bg-accent hover:text-accent-foreground transition-colors " +
                    (selected ? "font-semibold text-foreground" : "text-muted-foreground")
                  }
                >
                  <span className="truncate">{meta.name}</span>
                  {selected && <span className="ml-auto text-xs">✓</span>}
                </button>
              );
            })}
          </div>,
          portalRoot,
        )
      : null;

  return (
    <div ref={containerRef} className="relative inline-flex">
      <Button
        ghost
        onClick={() => setOpen((v) => !v)}
        title={t.language.switchTo}
        aria-label={t.language.switchTo}
        aria-haspopup="listbox"
        aria-expanded={open}
        className="px-2 py-1 normal-case tracking-normal font-normal text-xs text-muted-foreground hover:text-foreground"
      >
        <Typography
          mondwest
          className="hidden sm:inline tracking-wide uppercase text-[0.65rem]"
        >
          {locale === "en" ? "EN" : current.name}
        </Typography>
      </Button>

      {menu}
    </div>
  );
}

interface LanguageSwitcherProps {
  dropUp?: boolean;
}
