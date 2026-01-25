/**
 * PickDetail — Sidebar entity view for a selected draft pick
 *
 * Shows detailed pick information when a pick pill is clicked from DraftAssetsRow.
 *
 * Sections:
 * 1. Pick header (year, round, team badge)
 * 2. Pick metadata (asset type, origin/destination)
 * 3. Protections (if any)
 * 4. Conveyance history (timeline of how pick moved)
 */

import { cx } from "@/lib/utils";
import type { PickEntity } from "@/state/shell";
import { usePickDetail, useTeams } from "../../../hooks";
import { PickHeader } from "./PickHeader";
import { PickTransfer } from "./PickTransfer";
import { AssetTypeBadge, ProtectionsSection, PickDescription } from "./PickMeta";
import { ConveyanceHistory } from "./ConveyanceHistory";
import { PickDetailSkeleton } from "./PickDetailSkeleton";

// ============================================================================
// Types
// ============================================================================

export interface PickDetailProps {
  /** Pick entity from sidebar stack */
  entity: PickEntity;
  /** Additional className */
  className?: string;
}

// ============================================================================
// Main Component
// ============================================================================

/**
 * PickDetail — Full pick detail view for sidebar
 */
export function PickDetail({ entity, className }: PickDetailProps) {
  const { getTeam } = useTeams();

  const { pick, isLoading, error } = usePickDetail({
    teamCode: entity.teamCode,
    year: entity.draftYear,
    round: entity.draftRound,
  });

  const team = getTeam(entity.teamCode);
  const teamName = team?.name ?? entity.teamCode;

  if (isLoading) {
    return <PickDetailSkeleton />;
  }

  if (error) {
    return (
      <div className={cx("space-y-4", className)}>
        <PickHeader
          year={entity.draftYear}
          round={entity.draftRound}
          teamCode={entity.teamCode}
          teamName={teamName}
          isSwap={false}
        />
        <div className="p-4 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
          <div className="text-sm text-red-700 dark:text-red-400">
            {error.message}
          </div>
        </div>

        {entity.rawFragment && <PickDescription description={entity.rawFragment} />}
      </div>
    );
  }

  if (!pick) {
    return (
      <div className={cx("space-y-4", className)}>
        <PickHeader
          year={entity.draftYear}
          round={entity.draftRound}
          teamCode={entity.teamCode}
          teamName={teamName}
          isSwap={false}
        />
        <div className="p-4 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
          <div className="text-sm text-amber-700 dark:text-amber-400">
            Pick data not found in database
          </div>
        </div>

        {entity.rawFragment && <PickDescription description={entity.rawFragment} />}
      </div>
    );
  }

  const originTeamName =
    pick.origin_team?.team_name ?? getTeam(pick.origin_team_code)?.name ?? null;
  const destinationTeamName = pick.destination_team?.team_name ?? team?.name ?? null;

  return (
    <div className={cx("space-y-6", className)}>
      <PickHeader
        year={pick.year}
        round={pick.round}
        teamCode={pick.team_code}
        teamName={destinationTeamName ?? pick.team_code}
        isSwap={pick.is_swap}
      />

      {pick.asset_type && (
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted-foreground">Status:</span>
          <AssetTypeBadge assetType={pick.asset_type} />
        </div>
      )}

      <PickTransfer
        originTeamCode={pick.origin_team_code}
        originTeamName={originTeamName}
        destinationTeamCode={pick.team_code}
        destinationTeamName={destinationTeamName}
      />

      {pick.protections && <ProtectionsSection protections={pick.protections} />}

      {pick.description && <PickDescription description={pick.description} />}

      <ConveyanceHistory />
    </div>
  );
}
