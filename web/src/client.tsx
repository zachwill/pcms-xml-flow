import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { SalaryBook } from "@/features/SalaryBook";
import { ToastProvider } from "@/components/ui";

function App() {
  return (
    <ToastProvider>
      <BrowserRouter>
        <Routes>
          {/* Salary Book is the app */}
          <Route path="/" element={<SalaryBook />} />

          {/* Backwards-compatible alias */}
          <Route path="/salary-book" element={<Navigate to="/" replace />} />

          {/* Everything else redirects to the app */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </ToastProvider>
  );
}

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(<App />);
}
