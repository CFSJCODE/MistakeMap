-- Migration: Fix infinite recursion in user_manage_own_profile policy
-- The WITH CHECK clause had a subquery SELECT from profiles inside a profiles policy,
-- causing "infinite recursion detected in policy" when any UPDATE runs (including admin role changes).
-- Fix: replace inline subquery with a SECURITY DEFINER function (same pattern as is_admin()).

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

DROP POLICY IF EXISTS "user_manage_own_profile" ON public.profiles;

CREATE POLICY "user_manage_own_profile"
  ON public.profiles FOR ALL
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    AND role = public.current_user_role()
  );
