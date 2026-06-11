"use client";

import type {
  InputHTMLAttributes,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from "react";

import { cn } from "@/lib/cn";

/** admin.css `.input` — 14.5px, 11×13 padding, 1.5px border, brand-int focus with the
 * 4px `--focus-ring` glow; `.input.err` swaps the border to danger. */
const FIELD =
  "w-full rounded-md border-[1.5px] border-border-strong bg-surface px-[13px] py-[11px] font-sans text-[14.5px] text-text-strong transition-[border-color,box-shadow] duration-150 outline-none placeholder:text-faint focus:border-brand-int focus:shadow-[0_0_0_4px_var(--focus-ring)] disabled:cursor-not-allowed disabled:opacity-60";

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  error?: boolean;
}

export function Input({ error, className, ...props }: InputProps) {
  return (
    <input
      aria-invalid={error || undefined}
      className={cn(FIELD, error && "border-danger focus:border-danger", className)}
      {...props}
    />
  );
}

export interface TextareaProps
  extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  error?: boolean;
}

export function Textarea({ error, className, ...props }: TextareaProps) {
  return (
    <textarea
      aria-invalid={error || undefined}
      className={cn(FIELD, "min-h-24 resize-y", error && "border-danger focus:border-danger", className)}
      {...props}
    />
  );
}

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  error?: boolean;
}

export function Select({ error, className, ...props }: SelectProps) {
  return (
    <select
      aria-invalid={error || undefined}
      className={cn(FIELD, error && "border-danger focus:border-danger", className)}
      {...props}
    />
  );
}

/** admin.css `.field` — label 13px semibold with 7px gap; `.hint` 12px (error → danger). */
export function Field({
  label,
  required,
  hint,
  error,
  className,
  children,
}: {
  label: string;
  required?: boolean;
  hint?: string;
  error?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={cn("mb-4", className)}>
      <label className="mb-[7px] block text-[13px] font-semibold text-text">
        {label}
        {required ? <span className="text-danger"> *</span> : null}
      </label>
      {children}
      {error ? (
        <p className="mt-1.5 text-xs text-danger">{error}</p>
      ) : hint ? (
        <p className="mt-1.5 text-xs text-muted">{hint}</p>
      ) : null}
    </div>
  );
}
