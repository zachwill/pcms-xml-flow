/**
 * Loading skeleton for pick detail
 */
export function PickDetailSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      {/* Header skeleton */}
      <div className="flex items-start gap-4">
        <div className="w-16 h-16 rounded-xl bg-muted" />
        <div className="flex-1 space-y-2">
          <div className="h-6 w-40 bg-muted rounded" />
          <div className="h-4 w-28 bg-muted rounded" />
        </div>
      </div>

      {/* Transfer skeleton */}
      <div className="space-y-2">
        <div className="h-3 w-20 bg-muted rounded" />
        <div className="flex gap-2">
          <div className="flex-1 h-20 bg-muted/30 rounded-lg" />
          <div className="w-5 h-5 bg-muted rounded self-center" />
          <div className="flex-1 h-20 bg-muted/30 rounded-lg" />
        </div>
      </div>

      {/* Description skeleton */}
      <div className="space-y-2">
        <div className="h-3 w-24 bg-muted rounded" />
        <div className="h-16 bg-muted/30 rounded-lg" />
      </div>
    </div>
  );
}
