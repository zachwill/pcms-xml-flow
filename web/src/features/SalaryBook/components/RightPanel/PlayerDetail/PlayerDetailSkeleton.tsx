/**
 * Loading skeleton for player detail
 */
export function PlayerDetailSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      {/* Header skeleton - horizontal layout */}
      <div className="flex items-center gap-4">
        <div className="w-20 h-20 rounded border border-border bg-muted shrink-0" />
        <div className="space-y-2">
          <div className="h-5 w-36 bg-muted rounded" />
          <div className="h-4 w-28 bg-muted rounded" />
          <div className="h-3 w-24 bg-muted rounded" />
        </div>
      </div>

      {/* Contract skeleton */}
      <div className="space-y-3">
        <div className="h-3 w-20 bg-muted rounded" />
        <div className="p-4 rounded-lg bg-muted/30 space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="flex justify-between">
              <div className="h-4 w-24 bg-muted rounded" />
              <div className="h-4 w-16 bg-muted rounded" />
            </div>
          ))}
        </div>
      </div>

      {/* Year-by-year skeleton */}
      <div className="space-y-3">
        <div className="h-3 w-24 bg-muted rounded" />
        <div className="space-y-2">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-10 bg-muted/30 rounded" />
          ))}
        </div>
      </div>
    </div>
  );
}
