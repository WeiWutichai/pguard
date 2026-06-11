import { cn } from "@/lib/cn";

export type AvatarStatus = "active" | "working" | "offline";

const STATUS_BG: Record<AvatarStatus, string> = {
  active: "bg-status-active",
  working: "bg-status-working",
  offline: "bg-status-offline",
};

export interface AvatarProps {
  /** Initials (the design shows 2 Thai/Latin chars). */
  children: React.ReactNode;
  /** Guard live-status indicator dot (admin.css `.cell-user .av .ind`). */
  status?: AvatarStatus;
  size?: "sm" | "md" | "lg";
  className?: string;
}

/** admin.css `.cell-user .av` / `.um-av` — green-tinted initials circle that inverts in
 * dark mode, with an optional surface-ringed status dot. */
export function Avatar({ children, status, size = "md", className }: AvatarProps) {
  return (
    <span
      className={cn(
        "relative flex flex-none items-center justify-center rounded-full bg-green-100 font-latin font-semibold text-green-800 dark:bg-green-800 dark:text-green-100",
        size === "sm" && "size-[30px] text-xs",
        size === "md" && "size-9 text-[13px]",
        size === "lg" && "size-[42px] text-[15px]",
        className,
      )}
    >
      {children}
      {status ? (
        <span
          className={cn(
            "absolute -bottom-px -right-px size-[11px] rounded-full border-2 border-surface",
            STATUS_BG[status],
          )}
        />
      ) : null}
    </span>
  );
}
