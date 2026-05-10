import { Link } from "react-router-dom";
import { useSidebarStatus } from "@/hooks/useSidebarStatus";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n";

/** Gateway + session summary for the System sidebar block (no separate strip chrome). */
export function SidebarStatusStrip() {
  const status = useSidebarStatus();
  const { t } = useI18n();

  if (status === null) {
    return (
      <div className="px-5 py-1.5" aria-hidden>
        <div className="h-2 w-[80%] max-w-full animate-pulse rounded-sm bg-midground/10" />
      </div>
    );
  }

  const { activeSessionsLabel, webChatReady, webChatStatusLabel } = t.app;

  return (
    <Link
      to="/sessions"
      title={t.app.statusOverview}
      className={cn(
        "block text-left",
        "px-5 pb-2 pt-0.5",
        "text-muted-foreground/70",
        "transition-colors hover:text-muted-foreground/90",
        "focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-midground/40",
        "focus-visible:ring-inset",
      )}
    >
      <div className="flex flex-col gap-1 font-mondwest text-[0.55rem] leading-snug tracking-[0.12em]">
        <p className="break-words">
          <span className="text-muted-foreground/50">{webChatStatusLabel}</span>{" "}
          <span className="font-medium text-success">{webChatReady}</span>
        </p>

        <p className="break-words">
          <span className="text-muted-foreground/50">{activeSessionsLabel}</span>{" "}
          <span className="tabular-nums text-muted-foreground/70">
            {status.active_sessions}
          </span>
        </p>
      </div>
    </Link>
  );
}
