/**
 * SalaryBook — View
 *
 * The Salary Book is one view rendered inside the invariant AppShell.
 * The shell owns:
 * - fixed top nav / filters
 * - scroll-spy context
 * - sidebar state machine
 */

import { AppShell } from "@/components/app";
import { MainCanvas } from "./components/MainCanvas";
import { SidebarPanel } from "./components/Sidebar";

export function SalaryBook() {
  return <AppShell main={<MainCanvas />} sidebar={<SidebarPanel />} />;
}
