-- Intentionally reserved migration number.
--
-- Why this exists:
-- - Migration 009 was skipped historically.
-- - We keep this explicit no-op file so future agents/contributors
--   do not reuse 009 and create ordering ambiguity.

DO $$
BEGIN
    NULL;
END
$$;
