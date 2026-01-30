/**
 * SalaryBookPage — Salary Book view shell
 *
 * Composes the SalaryBook runtime provider, command bar, and layout frame.
 */

import { ThreePaneFrame } from "@/layouts/ThreePaneFrame";
import {
  SalaryBookShellProvider,
} from "@/features/SalaryBook/shell";
import {
  SalaryBookCommandBar,
  SALARY_BOOK_COMMAND_BAR_HEIGHT,
} from "@/features/SalaryBook/shell/CommandBar";
import { MainCanvas } from "../components/MainCanvas";
import { RightPanel } from "../components/RightPanel";

export function SalaryBookPage() {
  return (
    <SalaryBookShellProvider topOffset={0}>
      <ThreePaneFrame
        header={<SalaryBookCommandBar />}
        headerHeight={SALARY_BOOK_COMMAND_BAR_HEIGHT}
        main={<MainCanvas />}
        right={<RightPanel />}
      />
    </SalaryBookShellProvider>
  );
}
