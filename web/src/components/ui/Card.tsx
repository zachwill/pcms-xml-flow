import React from "react"
import { cx } from "@/lib/utils"

interface CardProps extends React.ComponentPropsWithoutRef<"div"> {}

const Card = React.forwardRef<HTMLDivElement, CardProps>(
  ({ className, ...props }, forwardedRef) => {
    return (
      <div
        ref={forwardedRef}
        className={cx(
          // base
          "relative w-full rounded-md border p-6 text-left",
          // background color
          "bg-background",
          // border color
          "border-border",
          className,
        )}
        {...props}
      />
    )
  },
)
Card.displayName = "Card"

export { Card, type CardProps }
