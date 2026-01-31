import { cx } from "@/lib/utils";
import type { PickDetailEndnote, PickDetailTradeClaims } from "../../../hooks";

function Badge({
  label,
  tone = "muted",
}: {
  label: string;
  tone?: "muted" | "amber" | "red" | "blue";
}) {
  const toneClasses = {
    muted: "bg-muted/60 text-muted-foreground",
    amber: "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-200",
    red: "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-200",
    blue: "bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-200",
  };

  return (
    <span
      className={cx(
        "px-1.5 py-0.5 rounded-full",
        "text-[9px] font-semibold uppercase tracking-wide",
        toneClasses[tone]
      )}
    >
      {label}
    </span>
  );
}

function EndnoteCard({ note }: { note: PickDetailEndnote }) {
  const detailLines = [
    note.trade_summary,
    note.conveyance_text,
    note.protections_text,
    note.contingency_text,
    note.exercise_text,
    note.explanation,
  ].filter((line, index, arr) => line && arr.indexOf(line) === index) as string[];

  const [primaryLine, ...secondaryLines] = detailLines;

  return (
    <div className="rounded-md border border-border/50 bg-muted/30 px-3 py-2 space-y-1">
      <div className="flex items-start justify-between gap-2">
        <div className="space-y-1">
          <div className="text-sm font-medium text-foreground">
            Endnote {note.endnote_id}
          </div>
          <div className="text-[11px] text-muted-foreground">
            {note.trade_date ?? "Date TBD"}
          </div>
        </div>
        <div className="flex flex-wrap gap-1 justify-end">
          {note.note_type && <Badge label={note.note_type} tone="blue" />}
          {note.status_lk && <Badge label={note.status_lk} tone="muted" />}
          {note.is_frozen_pick ? <Badge label="Frozen" tone="red" /> : null}
          {note.has_rollover ? <Badge label="Rollover" tone="amber" /> : null}
        </div>
      </div>

      {primaryLine ? (
        <div className="text-sm text-foreground/90">{primaryLine}</div>
      ) : (
        <div className="text-sm text-muted-foreground italic">
          No detailed explanation available.
        </div>
      )}

      {secondaryLines.length > 0 && (
        <div className="space-y-0.5 text-[11px] text-muted-foreground">
          {secondaryLines.map((line) => (
            <div key={line}>• {line}</div>
          ))}
        </div>
      )}

      {note.depends_on_endnotes.length > 0 && (
        <div className="text-[10px] text-muted-foreground">
          Depends on endnotes: {note.depends_on_endnotes.join(", ")}
        </div>
      )}
    </div>
  );
}

function TradeClaimsSection({ tradeClaims }: { tradeClaims: PickDetailTradeClaims }) {
  const claims = tradeClaims.trade_claims ?? [];

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Trade Claims
        </div>
        <div className="text-[10px] text-muted-foreground tabular-nums">
          {tradeClaims.claims_count} claims
        </div>
      </div>

      <div className="text-[11px] text-muted-foreground">
        Original slot: {tradeClaims.original_team_code}
        {tradeClaims.latest_trade_date
          ? ` · Latest ${tradeClaims.latest_trade_date}`
          : ""}
      </div>

      {claims.length === 0 ? (
        <div className="p-3 rounded-lg bg-muted/20 border border-dashed border-border text-sm text-muted-foreground italic">
          No trade claims recorded for this slot.
        </div>
      ) : (
        <div className="space-y-2">
          {claims.map((claim, index) => (
            <div
              key={`${claim.trade_id ?? index}-${claim.to_team_code ?? ""}`}
              className="rounded-md border border-border/50 bg-muted/30 px-3 py-2 space-y-1"
            >
              <div className="flex items-center justify-between gap-2">
                <div className="text-sm font-medium text-foreground">
                  {(claim.from_team_code ?? "?") + " → " + (claim.to_team_code ?? "?")}
                </div>
                <div className="text-[10px] text-muted-foreground">
                  {claim.trade_date ?? "Date TBD"}
                </div>
              </div>
              <div className="flex flex-wrap gap-1">
                {claim.is_swap ? <Badge label="Swap" tone="amber" /> : null}
                {claim.is_conditional ? <Badge label="Conditional" tone="amber" /> : null}
                {claim.conditional_type_lk ? (
                  <Badge label={claim.conditional_type_lk} tone="muted" />
                ) : null}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/**
 * Conveyance history / endnotes
 */
export function ConveyanceHistory({
  endnotes,
  tradeClaims,
  missingEndnoteRefs,
  draftYear,
}: {
  endnotes: PickDetailEndnote[];
  tradeClaims: PickDetailTradeClaims | null;
  missingEndnoteRefs: number[];
  draftYear?: number | null;
}) {
  if (endnotes.length === 0 && !tradeClaims) {
    return (
      <div className="space-y-2">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Conveyance History
        </div>
        <div
          className={cx(
            "p-3 rounded-lg",
            "bg-muted/20 border border-dashed border-border"
          )}
        >
          <p className="text-sm text-muted-foreground italic">
            No endnote or trade-claim history available for {draftYear ?? "this"} pick.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Conveyance History
      </div>

      {endnotes.length > 0 && (
        <div className="space-y-2">
          <div className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
            Endnotes
          </div>
          <div className="space-y-2">
            {endnotes.map((note) => (
              <EndnoteCard key={note.endnote_id} note={note} />
            ))}
          </div>
        </div>
      )}

      {missingEndnoteRefs.length > 0 && (
        <div className="text-[11px] text-muted-foreground">
          Missing endnote refs: {missingEndnoteRefs.join(", ")}
        </div>
      )}

      {tradeClaims && <TradeClaimsSection tradeClaims={tradeClaims} />}
    </div>
  );
}
