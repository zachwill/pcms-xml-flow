import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { SWRConfig } from "swr";
import { SalaryBookPage } from "@/features/SalaryBook";
import { ToastProvider } from "@/components/ui";
import { FilterProvider } from "@/state/filters";

function App() {
  return (
    <ToastProvider>
      <SWRConfig
        value={{
          revalidateOnFocus: false,
          revalidateOnReconnect: true,
          dedupingInterval: 5000,
        }}
      >
        <FilterProvider>
          <BrowserRouter>
            <Routes>
              {/* Salary Book is the only active view today */}
              <Route path="/" element={<SalaryBookPage />} />

              {/* Backwards-compatible alias */}
              <Route path="/salary-book" element={<Navigate to="/" replace />} />

              {/* Everything else redirects to the app */}
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </BrowserRouter>
        </FilterProvider>
      </SWRConfig>
    </ToastProvider>
  );
}

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(<App />);
}
