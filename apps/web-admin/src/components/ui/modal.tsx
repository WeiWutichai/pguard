"use client";

import { useEffect } from "react";
import type { ReactNode } from "react";
import { X } from "lucide-react";

import { cn } from "@/lib/cn";

export interface ModalProps {
  open: boolean;
  onClose: () => void;
  title?: ReactNode;
  /** admin.css `.modal` 520px / `.modal.lg` 680px. */
  size?: "md" | "lg";
  footer?: ReactNode;
  children: ReactNode;
  className?: string;
}

/** admin.css `.overlay` + `.modal` — blurred scrim, 14px-radius dialog, head/body/foot
 * hairlines. Closes on Escape and on scrim click. */
export function Modal({ open, onClose, title, size = "md", footer, children, className }: ModalProps) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      // Scrim color is the design's own (admin.css .overlay) — a green-tinted ink, not a token var.
      className="fixed inset-0 z-100 flex animate-[pg-fade-in_0.2s_ease] items-center justify-center bg-[rgba(8,20,15,0.5)] p-6 backdrop-blur-[3px]"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        className={cn(
          "flex max-h-[88vh] w-[520px] max-w-full animate-[pg-modal-in_0.2s_ease] flex-col overflow-hidden rounded-xl border border-border bg-surface shadow-xl",
          size === "lg" && "w-[680px]",
          className,
        )}
        onClick={(e) => e.stopPropagation()}
      >
        {title !== undefined ? (
          <header className="flex items-center gap-3 border-b border-border px-[22px] py-[18px]">
            <h3 className="text-lg font-semibold text-text-strong">{title}</h3>
            <button
              type="button"
              aria-label="close"
              onClick={onClose}
              className="ml-auto flex size-[34px] cursor-pointer items-center justify-center rounded-[9px] text-faint hover:bg-sunken"
            >
              <X size={18} />
            </button>
          </header>
        ) : null}
        <div className="overflow-y-auto p-[22px]">{children}</div>
        {footer ? (
          <footer className="flex justify-end gap-2.5 border-t border-border px-[22px] py-4">
            {footer}
          </footer>
        ) : null}
      </div>
    </div>
  );
}
