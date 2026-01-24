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
 * 5. AI insights placeholder
 */

import { useState, useEffect } from "react";
import { cx } from "@/lib/utils";
import { useTeams } from "../../../hooks";
import type { PickEntity } from "../../../hooks";
import { AIInsightsPlaceholder } from "../../shared";
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

/**
 * Pick API response from /api/salary-book/pick
 */
interface PickApiResponse {
  team_code: string;
  year: number;
  round: number;
  asset_type: string | null;
  description: string | null;
  origin_team_code: string;
  origin_team: {
    team_code: string;
    team_name: string;
    team_nickname: string;
  } | null;
  destination_team: {
    team_code: string;
    team_name: string;
    team_nickname: string;
  } | null;
  protections: string | null;
  is_swap: boolean;
  all_slots: Array<{
    asset_slot: number;
    asset_type: string;
    description: string;
  }>;
}

// ============================================================================
// Main Component
// ============================================================================

/**
 * PickDetail — Full pick detail view for sidebar
 *
 * Fetches pick data from API to ensure complete information.
 * Shows pick metadata, origin/destination, protections, and conveyance history.
 */
export function PickDetail({ entity, className }: PickDetailProps) {
  const { getTeam } = useTeams();

  // State for fetched pick data
  const [pick, setPick] = useState<PickApiResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  // Fetch pick data
  useEffect(() => {
    async function fetchPick() {
      setIsLoading(true);
      setError(null);

      try {
        const params = new URLSearchParams({
          team: entity.teamCode,
          year: String(entity.draftYear),
          round: String(entity.draftRound),
        });

        const response = await fetch(`/api/salary-book/pick?${params}`);

        if (!response.ok) {
          throw new Error(`Failed to fetch pick: ${response.status}`);
        }

        const data = await response.json();
        setPick(data);
      } catch (err) {
        setError(err instanceof Error ? err : new Error(String(err)));
      } finally {
        setIsLoading(false);
      }
    }

    fetchPick();
  }, [entity.teamCode, entity.draftYear, entity.draftRound]);

  // Get team info from local data as fallback
  const team = getTeam(entity.teamCode);
  const teamName = team?.name ?? entity.teamCode;

  // Show skeleton while loading
  if (isLoading) {
    return <PickDetailSkeleton />;
  }

  // Show error state
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

        {/* Still show entity raw data */}
        {entity.rawFragment && (
          <PickDescription description={entity.rawFragment} />
        )}
      </div>
    );
  }

  // No data returned
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

        {/* Show entity raw data as fallback */}
        {entity.rawFragment && (
          <PickDescription description={entity.rawFragment} />
        )}
      </div>
    );
  }

  // Derive display values
  const originTeamName =
    pick.origin_team?.team_name ?? getTeam(pick.origin_team_code)?.name ?? null;
  const destinationTeamName =
    pick.destination_team?.team_name ?? team?.name ?? null;

  return (
    <div className={cx("space-y-6", className)}>
      {/* Pick Header */}
      <PickHeader
        year={pick.year}
        round={pick.round}
        teamCode={pick.team_code}
        teamName={destinationTeamName ?? pick.team_code}
        isSwap={pick.is_swap}
      />

      {/* Asset Type */}
      {pick.asset_type && (
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted-foreground">Status:</span>
          <AssetTypeBadge assetType={pick.asset_type} />
        </div>
      )}

      {/* Origin/Destination Transfer */}
      <PickTransfer
        originTeamCode={pick.origin_team_code}
        originTeamName={originTeamName}
        destinationTeamCode={pick.team_code}
        destinationTeamName={destinationTeamName}
      />

      {/* Protections */}
      {pick.protections && <ProtectionsSection protections={pick.protections} />}

      {/* Pick Description */}
      {pick.description && <PickDescription description={pick.description} />}

      {/* Conveyance History */}
      <ConveyanceHistory />

      {/* AI Insights Placeholder */}
      <AIInsightsPlaceholder
        description="AI-powered pick valuation, protection analysis, and trade scenario modeling coming soon."
      />
    </div>
  );
}
