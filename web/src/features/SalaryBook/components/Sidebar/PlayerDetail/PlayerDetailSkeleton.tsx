/**
 * Loading skeleton for player detail
 */
export function PlayerDetailSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      {/* Header skeleton */}
      <div className="flex flex-col items-center space-y-3">
        <div className="w-20 h-20 rounded-full bg-muted" />
        <div className="space-y-2 text-center">
          <div className="h-6 w-40 bg-muted rounded mx-auto" />
          <div className="h-4 w-32 bg-muted rounded mx-auto" />
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
