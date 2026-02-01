import { useEffect, useMemo, useState } from "react";
import { cx, formatters } from "@/lib/utils";
import {
  Input,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Switch,
} from "@/components/ui";
import { useShellScrollContext } from "@/features/SalaryBook/shell";
import {
  useBuyoutScenario,
  usePlayers,
  useSetoffAmount,
  useSystemValues,
  useTeams,
} from "../../hooks";
import type { BuyoutScenarioRequest, SetoffAmountRequest } from "../../data";

const FALLBACK_YEARS = [2025, 2026, 2027, 2028, 2029];

function formatCurrency(value: number | null): string {
  return value === null ? "—" : formatters.compactCurrency(value);
}

function formatCurrencyFull(value: number | null): string {
  return value === null ? "—" : formatters.currency(value);
}

function formatPercent(value: number | null): string {
  return value === null ? "—" : formatters.percent(value);
}

function SectionTitle({ children }: { children: string }) {
  return (
    <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground mb-2">
      {children}
    </div>
  );
}

export function BuyoutCalculatorView({ className }: { className?: string }) {
  const { activeTeam } = useShellScrollContext();
  const { teams, getTeam } = useTeams();
  const { years: systemYears, getForYear } = useSystemValues();

  const yearOptions = systemYears.length > 0 ? systemYears : FALLBACK_YEARS;

  const [teamCode, setTeamCode] = useState<string | null>(activeTeam ?? null);
  const [salaryYear, setSalaryYear] = useState<number>(yearOptions[0] ?? 2025);
  const [playerId, setPlayerId] = useState<number | null>(null);
  const [waiveDate, setWaiveDate] = useState<string>("");
  const [giveBackAmount, setGiveBackAmount] = useState<string>("");
  const [stretchEnabled, setStretchEnabled] = useState<boolean>(false);

  const [setoffSalary, setSetoffSalary] = useState<string>("");
  const [setoffYos, setSetoffYos] = useState<string>("1");

  useEffect(() => {
    if (!teamCode && activeTeam) {
      setTeamCode(activeTeam);
    }
  }, [teamCode, activeTeam]);

  useEffect(() => {
    if (!yearOptions.includes(salaryYear)) {
      setSalaryYear(yearOptions[0] ?? 2025);
    }
  }, [salaryYear, yearOptions]);

  const { players, isLoading: playersLoading } = usePlayers(teamCode);

  const playerOptions = useMemo(() => {
    return players
      .map((player) => ({
        id: Number(player.player_id),
        name: player.player_name,
      }))
      .filter((player) => Number.isFinite(player.id));
  }, [players]);

  const playersMatchTeam = useMemo(() => {
    if (!teamCode || players.length === 0) return false;
    return players.every((player) => player.team_code === teamCode);
  }, [players, teamCode]);

  useEffect(() => {
    setPlayerId(null);
  }, [teamCode]);

  useEffect(() => {
    if (!playerId && playersMatchTeam && playerOptions.length > 0) {
      setPlayerId(playerOptions[0].id);
    }
  }, [playerId, playerOptions, playersMatchTeam]);

  const parsedGiveBack = Number(giveBackAmount);
  const giveBackValue = Number.isFinite(parsedGiveBack) ? parsedGiveBack : 0;

  const request = useMemo<BuyoutScenarioRequest | null>(() => {
    if (!playerId || !waiveDate) return null;
    return {
      playerId,
      waiveDate,
      giveBackAmount: giveBackValue,
      salaryYear,
      league: "NBA",
    };
  }, [playerId, waiveDate, giveBackValue, salaryYear]);

  const { scenario, isLoading, error, isReady } = useBuyoutScenario(request);

  const systemValues = getForYear(salaryYear);
  const seasonStart = systemValues?.season_start_at ?? `${salaryYear}-10-20`;
  const teamLabel = teamCode ? getTeam(teamCode)?.name ?? teamCode : "—";

  const setoffSalaryValue = Number(setoffSalary);
  const setoffYosValue = Number(setoffYos);

  const setoffRequest = useMemo<SetoffAmountRequest | null>(() => {
    if (!Number.isFinite(setoffSalaryValue) || setoffSalaryValue <= 0) return null;
    const yos = Number.isFinite(setoffYosValue) && setoffYosValue > 0 ? setoffYosValue : 1;
    return {
      newSalary: setoffSalaryValue,
      salaryYear,
      yearsOfService: yos,
      league: "NBA",
    };
  }, [setoffSalaryValue, setoffYosValue, salaryYear]);

  const {
    setoff,
    isLoading: setoffLoading,
    error: setoffError,
    isReady: setoffReady,
  } = useSetoffAmount(setoffRequest);

  const rows = scenario?.rows ?? [];
  const totals = scenario?.totals ?? null;
  const stretch = scenario?.stretch ?? null;

  const capTotal = useMemo(() => {
    if (rows.length === 0) return null;
    return rows.reduce((sum, row) => sum + (row.cap_salary ?? 0), 0);
  }, [rows]);

  return (
    <div className={cx("space-y-4", className)}>
      <div className="space-y-1">
        <div className="text-sm font-semibold">Waive / Buyout / Stretch</div>
        <div className="text-xs text-muted-foreground">
          Scenario math via pcms.fn_buyout_scenario + stretch provision.
        </div>
      </div>

      <div className="border-t border-border pt-4">
        <SectionTitle>Setup</SectionTitle>
        <div className="space-y-2">
          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">Team</span>
            <div className="w-[170px]">
              <Select
                value={teamCode ?? "none"}
                onValueChange={(value) => setTeamCode(value === "none" ? null : value)}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select team" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">None</SelectItem>
                  {teams.map((team) => (
                    <SelectItem key={team.team_code} value={team.team_code}>
                      {team.team_code} — {team.nickname}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">Player</span>
            <div className="w-[200px]">
              <Select
                value={playerId ? String(playerId) : "none"}
                onValueChange={(value) =>
                  setPlayerId(value === "none" ? null : Number(value))
                }
                disabled={!teamCode || playersLoading}
              >
                <SelectTrigger>
                  <SelectValue placeholder={playersLoading ? "Loading…" : "Select player"} />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">None</SelectItem>
                  {playerOptions.map((player) => (
                    <SelectItem key={player.id} value={String(player.id)}>
                      {player.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">Season Year</span>
            <div className="w-[120px]">
              <Select
                value={String(salaryYear)}
                onValueChange={(value) => setSalaryYear(Number(value))}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Year" />
                </SelectTrigger>
                <SelectContent>
                  {yearOptions.map((year) => (
                    <SelectItem key={year} value={String(year)}>
                      {year}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">Season Start</span>
            <span className="text-xs font-mono tabular-nums">
              {seasonStart ?? "—"}
            </span>
          </div>

          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">Waive Date</span>
            <div className="w-[170px]">
              <Input
                type="date"
                value={waiveDate}
                onChange={(event) => setWaiveDate(event.target.value)}
              />
            </div>
          </div>

          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">Give Back</span>
            <div className="w-[170px]">
              <Input
                type="number"
                enableStepper={false}
                placeholder="$0"
                value={giveBackAmount}
                onChange={(event) => setGiveBackAmount(event.target.value)}
              />
            </div>
          </div>

          <div className="text-[11px] text-muted-foreground">
            {teamLabel !== "—" ? `${teamLabel} · ${teamCode ?? ""}` : ""}
          </div>
        </div>
      </div>

      <div className="border-t border-border pt-4">
        <SectionTitle>Scenario</SectionTitle>
        {!isReady ? (
          <div className="text-xs text-muted-foreground">
            Select a player and waive date to run the buyout math.
          </div>
        ) : isLoading ? (
          <div className="text-xs text-muted-foreground">Calculating buyout scenario…</div>
        ) : error ? (
          <div className="text-xs text-red-500">{error.message}</div>
        ) : rows.length === 0 ? (
          <div className="text-xs text-muted-foreground">
            No salary rows found for this player/year.
          </div>
        ) : (
          <div className="space-y-2">
            <div className="grid grid-cols-[54px_1fr_1fr_1fr_1fr] gap-2 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
              <div>Year</div>
              <div className="text-right">Cap</div>
              <div className="text-right">Guaranteed</div>
              <div className="text-right">Give Back</div>
              <div className="text-right">Dead Money</div>
            </div>

            <div className="space-y-2">
              {rows.map((row) => (
                <div key={row.salary_year} className="space-y-1">
                  <div className="grid grid-cols-[54px_1fr_1fr_1fr_1fr] gap-2 text-xs">
                    <div className="font-mono tabular-nums">{row.salary_year}</div>
                    <div className="font-mono tabular-nums text-right">
                      {formatCurrency(row.cap_salary)}
                    </div>
                    <div className="font-mono tabular-nums text-right">
                      {formatCurrency(row.guaranteed_remaining)}
                    </div>
                    <div className="font-mono tabular-nums text-right">
                      {formatCurrency(row.give_back_amount)}
                    </div>
                    <div className="font-mono tabular-nums text-right">
                      {formatCurrency(row.dead_money)}
                    </div>
                  </div>
                  {row.days_remaining !== null ? (
                    <div className="pl-[54px] text-[10px] text-muted-foreground">
                      {row.days_remaining} days remaining · {formatPercent(row.proration_factor)}
                      {row.give_back_pct !== null
                        ? ` give-back share ${formatPercent(row.give_back_pct)}`
                        : ""}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>

            {totals ? (
              <div className="grid grid-cols-[54px_1fr_1fr_1fr_1fr] gap-2 border-t border-border pt-2 text-xs">
                <div className="text-[11px] font-semibold text-muted-foreground">Total</div>
                <div className="font-mono tabular-nums text-right">
                  {formatCurrencyFull(capTotal)}
                </div>
                <div className="font-mono tabular-nums text-right">
                  {formatCurrencyFull(totals.guaranteed_remaining)}
                </div>
                <div className="font-mono tabular-nums text-right">
                  {formatCurrencyFull(totals.give_back_amount)}
                </div>
                <div className="font-mono tabular-nums text-right">
                  {formatCurrencyFull(totals.dead_money)}
                </div>
              </div>
            ) : null}
          </div>
        )}
      </div>

      <div className="border-t border-border pt-4">
        <SectionTitle>Stretch Provision</SectionTitle>
        <div className="flex items-center justify-between gap-2">
          <span className="text-[11px] font-medium text-muted-foreground">
            Apply stretch (2 × remaining years + 1)
          </span>
          <Switch
            checked={stretchEnabled}
            onCheckedChange={(checked) => setStretchEnabled(checked)}
            size="small"
          />
        </div>

        {!stretchEnabled ? (
          <div className="text-xs text-muted-foreground mt-2">
            Toggle on to see stretched dead money schedule.
          </div>
        ) : !stretch ? (
          <div className="text-xs text-muted-foreground mt-2">
            Run a scenario with remaining salary to see stretch details.
          </div>
        ) : (
          <div className="space-y-2 mt-2">
            <div className="text-xs text-muted-foreground">
              {stretch.remaining_years ?? "—"} remaining years · {stretch.stretch_years ?? "—"} stretch seasons
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground">Annual Amount</span>
              <span className="font-mono tabular-nums">
                {formatCurrencyFull(stretch.annual_amount)}
              </span>
            </div>

            {stretch.schedule.length > 0 ? (
              <div className="space-y-1">
                <div className="grid grid-cols-[60px_1fr] gap-2 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
                  <div>Year</div>
                  <div className="text-right">Amount</div>
                </div>
                {stretch.schedule.map((entry, index) => (
                  <div
                    key={`${entry.year ?? "year"}-${index}`}
                    className="grid grid-cols-[60px_1fr] gap-2 text-xs"
                  >
                    <div className="font-mono tabular-nums">{entry.year ?? "—"}</div>
                    <div className="font-mono tabular-nums text-right">
                      {formatCurrency(entry.amount)}
                    </div>
                  </div>
                ))}
              </div>
            ) : null}
          </div>
        )}
      </div>

      <div className="border-t border-border pt-4">
        <SectionTitle>Set-Off Credit</SectionTitle>
        <div className="space-y-2">
          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">New Salary</span>
            <div className="w-[170px]">
              <Input
                type="number"
                enableStepper={false}
                placeholder="$0"
                value={setoffSalary}
                onChange={(event) => setSetoffSalary(event.target.value)}
              />
            </div>
          </div>

          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-muted-foreground">Years of Service</span>
            <div className="w-[120px]">
              <Input
                type="number"
                enableStepper={false}
                value={setoffYos}
                onChange={(event) => setSetoffYos(event.target.value)}
              />
            </div>
          </div>

          {!setoffReady ? (
            <div className="text-xs text-muted-foreground">
              Enter a new salary to compute the CBA set-off amount.
            </div>
          ) : setoffLoading ? (
            <div className="text-xs text-muted-foreground">Computing set-off…</div>
          ) : setoffError ? (
            <div className="text-xs text-red-500">{setoffError.message}</div>
          ) : setoff ? (
            <div className="space-y-1 text-xs">
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Minimum baseline</span>
                <span className="font-mono tabular-nums">
                  {formatCurrencyFull(setoff.minimum_salary)}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Set-off amount</span>
                <span className="font-mono tabular-nums">
                  {formatCurrencyFull(setoff.setoff_amount)}
                </span>
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
