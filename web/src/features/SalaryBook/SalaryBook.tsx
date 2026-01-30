/**
 * SalaryBook — Compatibility alias
 *
 * Keeps existing imports working while the view shell lives in SalaryBookPage.
 */

import { SalaryBookPage } from "./pages/SalaryBookPage";

export function SalaryBook() {
  return <SalaryBookPage />;
}
