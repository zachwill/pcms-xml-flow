/**
 * TeamSelectorGrid — Navigation grid for all 30 NBA teams
 *
 * Two conference blocks (Eastern, Western), each with 3 rows × 5 teams,
 * sorted by team code (tricode). Shows scroll-spy active team, loaded/unloaded states.
 *
 * Interactions:
 * - Click: Jump to team section (adds to loadedTeams if not loaded)
 * - Shift+Click: Toggle team in/out of loadedTeams without scrolling
 * - Alt+Click: Isolate single team view
 */

import { cx } from "@/lib/utils";
import { useShellContext } from "@/state/shell";
import { useTeams } from "@/features/SalaryBook/hooks";
import type { Team } from "@/features/SalaryBook/data";

interface TeamPillProps {
  team: Team;
  isActive: boolean;
  isLoaded: boolean;
  onClick: (e: React.MouseEvent) => void;
}

/**
 * Individual team pill button
 *
 * Visual states per spec:
 * - Active: Strong highlight (filled background) — currently in viewport via scroll-spy
 * - Loaded: Subtle indicator (dot + border) — team is in the scrollable canvas
 * - Unloaded: Muted/dimmed — team not currently loaded
 */
function TeamPill({ team, isActive, isLoaded, onClick }: TeamPillProps) {
  const isPortland = team.team_code === "POR";

  return (
    <button
      type="button"
      onClick={onClick}
      className={cx(
        // Base styles
        "relative h-7 px-2 rounded text-xs font-medium",
        "transition-all duration-150",
        "border",
        "outline-none",

        // Active state (scroll-spy highlight) — same for all teams
        isActive && [
          "bg-primary text-primary-foreground border-primary",
          "shadow-sm",
        ],

        // Portland special styling when not active
        !isActive && isPortland && isLoaded && [
          "bg-muted/50 text-red-600 dark:text-red-400 border-red-400 dark:border-red-500",
          "hover:bg-red-100 dark:hover:bg-red-900/40 hover:border-red-500 dark:hover:border-red-400",
        ],

        !isActive && isPortland && !isLoaded && [
          "bg-transparent text-red-400 dark:text-red-500 border-red-300 dark:border-red-700",
          "hover:bg-red-100 dark:hover:bg-red-900/40 hover:text-red-500 dark:hover:text-red-400 hover:border-red-400 dark:hover:border-red-600",
          "opacity-70",
        ],

        // Loaded but not active (non-Portland)
        !isActive && !isPortland && isLoaded && [
          "bg-muted/50 text-foreground border-border",
          "hover:bg-muted hover:border-foreground/20",
        ],

        // Unloaded (dimmed, non-Portland)
        !isActive && !isPortland && !isLoaded && [
          "bg-transparent text-muted-foreground/50 border-transparent",
          "hover:bg-muted/30 hover:text-muted-foreground hover:border-border/50",
          "opacity-60",
        ]
      )}
      title={`${team.name}${isActive ? ' (active)' : isLoaded ? ' (loaded)' : ' (not loaded)'}`}
    >
      {team.team_code}
    </button>
  );
}

interface ConferenceGridProps {
  label: string;
  teams: Team[];
  activeTeam: string | null;
  loadedTeams: string[];
  onTeamClick: (teamCode: string, e: React.MouseEvent) => void;
}

/**
 * Conference block with 3 rows × 5 teams grid
 */
function ConferenceGrid({
  label,
  teams,
  activeTeam,
  loadedTeams,
  onTeamClick,
}: ConferenceGridProps) {
  const loadedSet = new Set(loadedTeams);

  return (
    <div className="space-y-1">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
        {label}
      </div>
      <div className="grid grid-cols-5 gap-1">
        {teams.map((team) => (
          <TeamPill
            key={team.team_code}
            team={team}
            isActive={activeTeam === team.team_code}
            isLoaded={loadedSet.has(team.team_code)}
            onClick={(e) => onTeamClick(team.team_code, e)}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * TeamSelectorGrid — Main export
 *
 * Displays all 30 NBA teams in two conference grids.
 * Integrates with SalaryBookContext for:
 * - activeTeam (scroll-spy highlight)
 * - loadedTeams (which teams are in the canvas)
 * - scrollToTeam (jump navigation)
 */
export function TeamSelectorGrid() {
  const {
    activeTeam,
    loadedTeams,
    setLoadedTeams,
    scrollToTeam,
  } = useShellContext();

  const { teamsByConference, isLoading, error } = useTeams();

  /**
   * Handle team pill click with modifier support
   */
  const handleTeamClick = (teamCode: string, e: React.MouseEvent) => {
    const isLoaded = loadedTeams.includes(teamCode);

    if (e.altKey || e.metaKey) {
      // Alt/Cmd+Click: Isolate - show only this team
      setLoadedTeams([teamCode]);
      // Small delay to let state update before scrolling
      setTimeout(() => scrollToTeam(teamCode, "auto"), 0);
      return;
    }

    if (e.shiftKey) {
      // Shift+Click: Toggle loaded state without scrolling
      if (isLoaded) {
        // Remove team (but don't remove if it's the only one)
        if (loadedTeams.length > 1) {
          setLoadedTeams(loadedTeams.filter((t) => t !== teamCode));
        }
      } else {
        // Add team to loaded list (maintain alphabetical order)
        const newLoaded = [...loadedTeams, teamCode].sort((a, b) =>
          a.localeCompare(b)
        );
        setLoadedTeams(newLoaded);
      }
      return;
    }

    // Regular click: Jump to team (add if not loaded)
    if (!isLoaded) {
      // Add team in alphabetical order
      const newLoaded = [...loadedTeams, teamCode].sort((a, b) =>
        a.localeCompare(b)
      );
      setLoadedTeams(newLoaded);
      // Wait for DOM update before scrolling
      setTimeout(() => scrollToTeam(teamCode, "smooth"), 0);
    } else {
      scrollToTeam(teamCode, "smooth");
    }
  };

  // Loading state
  if (isLoading) {
    return (
      <div className="flex gap-6">
        <div className="space-y-1">
          <div className="h-3 w-16 bg-muted/50 rounded animate-pulse" />
          <div className="grid grid-cols-5 gap-1">
            {Array.from({ length: 15 }).map((_, i) => (
              <div key={i} className="h-7 bg-muted/30 rounded animate-pulse" />
            ))}
          </div>
        </div>
        <div className="space-y-1">
          <div className="h-3 w-16 bg-muted/50 rounded animate-pulse" />
          <div className="grid grid-cols-5 gap-1">
            {Array.from({ length: 15 }).map((_, i) => (
              <div key={i} className="h-7 bg-muted/30 rounded animate-pulse" />
            ))}
          </div>
        </div>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="text-sm text-red-500">
        Failed to load teams: {error.message}
      </div>
    );
  }

  return (
    <div className="flex gap-6">
      <ConferenceGrid
        label="Eastern"
        teams={teamsByConference.EAST}
        activeTeam={activeTeam}
        loadedTeams={loadedTeams}
        onTeamClick={handleTeamClick}
      />
      <ConferenceGrid
        label="Western"
        teams={teamsByConference.WEST}
        activeTeam={activeTeam}
        loadedTeams={loadedTeams}
        onTeamClick={handleTeamClick}
      />
    </div>
  );
}
