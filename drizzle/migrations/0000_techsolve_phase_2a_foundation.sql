CREATE TYPE public.app_role AS ENUM ('user', 'admin');

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text UNIQUE CHECK (username IS NULL OR username ~ '^[A-Za-z0-9_]{3,30}$'),
  display_name text CHECK (display_name IS NULL OR char_length(display_name) <= 120),
  avatar_url text CHECK (avatar_url IS NULL OR char_length(avatar_url) <= 2048),
  bio text CHECK (bio IS NULL OR char_length(bio) <= 1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.profiles TO anon;
GRANT SELECT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL DEFAULT 'user',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE CHECK (char_length(name) BETWEEN 1 AND 80),
  description text CHECK (description IS NULL OR char_length(description) <= 500),
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.categories TO anon, authenticated;
GRANT ALL ON public.categories TO service_role;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.problems (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 3 AND 180),
  description text NOT NULL CHECK (char_length(btrim(description)) BETWEEN 10 AND 20000),
  category_id uuid NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
  tags text[] NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'solved')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (cardinality(tags) <= 20)
);
GRANT SELECT ON public.problems TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.problems TO authenticated;
GRANT ALL ON public.problems TO service_role;
ALTER TABLE public.problems ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  problem_id uuid NOT NULL REFERENCES public.problems(id) ON DELETE CASCADE,
  author_id uuid NOT NULL,
  content text NOT NULL CHECK (char_length(btrim(content)) BETWEEN 1 AND 20000),
  is_accepted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.answers TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.answers TO authenticated;
GRANT ALL ON public.answers TO service_role;
ALTER TABLE public.answers ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL,
  problem_id uuid REFERENCES public.problems(id) ON DELETE CASCADE,
  answer_id uuid REFERENCES public.answers(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (char_length(btrim(content)) BETWEEN 1 AND 5000),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((problem_id IS NOT NULL) <> (answer_id IS NOT NULL))
);
GRANT SELECT ON public.comments TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.comments TO authenticated;
GRANT ALL ON public.comments TO service_role;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  target_type text NOT NULL CHECK (target_type IN ('problem', 'answer')),
  target_id uuid NOT NULL,
  vote_type smallint NOT NULL CHECK (vote_type IN (-1, 1)),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, target_type, target_id)
);
GRANT SELECT ON public.votes TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.votes TO authenticated;
GRANT ALL ON public.votes TO service_role;
ALTER TABLE public.votes ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.bookmarks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  problem_id uuid NOT NULL REFERENCES public.problems(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, problem_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bookmarks TO authenticated;
GRANT ALL ON public.bookmarks TO service_role;
ALTER TABLE public.bookmarks ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL,
  target_type text NOT NULL CHECK (target_type IN ('problem', 'answer', 'comment')),
  target_id uuid NOT NULL,
  reason text NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 2000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.reports TO authenticated;
GRANT UPDATE, DELETE ON public.reports TO authenticated;
GRANT ALL ON public.reports TO service_role;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

CREATE INDEX problems_author_created_idx ON public.problems (author_id, created_at DESC);
CREATE INDEX problems_category_created_idx ON public.problems (category_id, created_at DESC);
CREATE INDEX problems_status_created_idx ON public.problems (status, created_at DESC);
CREATE INDEX answers_problem_created_idx ON public.answers (problem_id, created_at);
CREATE INDEX answers_author_created_idx ON public.answers (author_id, created_at DESC);
CREATE UNIQUE INDEX answers_one_accepted_per_problem_idx ON public.answers (problem_id) WHERE is_accepted;
CREATE INDEX comments_problem_created_idx ON public.comments (problem_id, created_at) WHERE problem_id IS NOT NULL;
CREATE INDEX comments_answer_created_idx ON public.comments (answer_id, created_at) WHERE answer_id IS NOT NULL;
CREATE INDEX votes_target_idx ON public.votes (target_type, target_id);
CREATE INDEX bookmarks_user_created_idx ON public.bookmarks (user_id, created_at DESC);
CREATE INDEX reports_status_created_idx ON public.reports (status, created_at DESC);
CREATE INDEX reports_reporter_created_idx ON public.reports (reporter_id, created_at DESC);

CREATE FUNCTION public.has_role(_role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = _role
  );
$$;
REVOKE ALL ON FUNCTION public.has_role(public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(public.app_role) TO authenticated;

CREATE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.create_auth_user_records()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    NULLIF(left(COALESCE(NEW.raw_user_meta_data ->> 'display_name', NEW.raw_user_meta_data ->> 'full_name', NEW.raw_user_meta_data ->> 'name', ''), 120), '')
  )
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'user')
  ON CONFLICT (user_id, role) DO NOTHING;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.create_auth_user_records() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER on_auth_user_created_create_records
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.create_auth_user_records();

CREATE FUNCTION public.validate_polymorphic_target()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  target_exists boolean := false;
BEGIN
  IF TG_TABLE_NAME = 'votes' THEN
    IF NEW.target_type = 'problem' THEN
      SELECT EXISTS (SELECT 1 FROM public.problems WHERE id = NEW.target_id) INTO target_exists;
    ELSIF NEW.target_type = 'answer' THEN
      SELECT EXISTS (SELECT 1 FROM public.answers WHERE id = NEW.target_id) INTO target_exists;
    END IF;
  ELSE
    IF NEW.target_type = 'problem' THEN
      SELECT EXISTS (SELECT 1 FROM public.problems WHERE id = NEW.target_id) INTO target_exists;
    ELSIF NEW.target_type = 'answer' THEN
      SELECT EXISTS (SELECT 1 FROM public.answers WHERE id = NEW.target_id) INTO target_exists;
    ELSIF NEW.target_type = 'comment' THEN
      SELECT EXISTS (SELECT 1 FROM public.comments WHERE id = NEW.target_id) INTO target_exists;
    END IF;
  END IF;
  IF NOT target_exists THEN
    RAISE EXCEPTION 'The selected % does not exist.', NEW.target_type
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.validate_polymorphic_target() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER votes_validate_target
BEFORE INSERT OR UPDATE OF target_type, target_id ON public.votes
FOR EACH ROW EXECUTE FUNCTION public.validate_polymorphic_target();
CREATE TRIGGER reports_validate_target
BEFORE INSERT OR UPDATE OF target_type, target_id ON public.reports
FOR EACH ROW EXECUTE FUNCTION public.validate_polymorphic_target();

CREATE FUNCTION public.validate_answer_acceptance()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  problem_author_id uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_accepted THEN
      RAISE EXCEPTION 'An answer can only be accepted after it has been created.' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.is_accepted IS DISTINCT FROM OLD.is_accepted THEN
    SELECT author_id INTO problem_author_id FROM public.problems WHERE id = NEW.problem_id;
    IF auth.uid() IS DISTINCT FROM problem_author_id
       AND NOT public.has_role('admin'::public.app_role) THEN
      RAISE EXCEPTION 'Only the problem author or an administrator can accept an answer.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.validate_answer_acceptance() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER answers_validate_acceptance
BEFORE INSERT OR UPDATE ON public.answers
FOR EACH ROW EXECUTE FUNCTION public.validate_answer_acceptance();

CREATE FUNCTION public.sync_problem_status_from_answer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  affected_problem_id uuid;
  should_sync boolean := false;
BEGIN
  IF TG_OP = 'DELETE' THEN
    affected_problem_id := OLD.problem_id;
    should_sync := OLD.is_accepted;
  ELSIF TG_OP = 'INSERT' THEN
    affected_problem_id := NEW.problem_id;
    should_sync := NEW.is_accepted;
  ELSE
    affected_problem_id := NEW.problem_id;
    should_sync := NEW.is_accepted IS DISTINCT FROM OLD.is_accepted;
  END IF;
  IF should_sync THEN
    UPDATE public.problems
    SET status = CASE WHEN EXISTS (
      SELECT 1 FROM public.answers WHERE problem_id = affected_problem_id AND is_accepted
    ) THEN 'solved' ELSE 'open' END,
    updated_at = now()
    WHERE id = affected_problem_id;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_problem_status_from_answer() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER answers_sync_problem_status
AFTER INSERT OR UPDATE OR DELETE ON public.answers
FOR EACH ROW EXECUTE FUNCTION public.sync_problem_status_from_answer();

CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER problems_set_updated_at BEFORE UPDATE ON public.problems
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER answers_set_updated_at BEFORE UPDATE ON public.answers
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY profiles_public_read ON public.profiles
FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY profiles_owner_or_admin_update ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id OR public.has_role('admin'::public.app_role))
WITH CHECK (auth.uid() = id OR public.has_role('admin'::public.app_role));
CREATE POLICY profiles_admin_delete ON public.profiles
FOR DELETE TO authenticated USING (public.has_role('admin'::public.app_role));

CREATE POLICY user_roles_read_own_or_admin ON public.user_roles
FOR SELECT TO authenticated
USING (auth.uid() = user_id OR public.has_role('admin'::public.app_role));

CREATE POLICY categories_public_read ON public.categories
FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY problems_public_read ON public.problems
FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY problems_authenticated_insert_own ON public.problems
FOR INSERT TO authenticated WITH CHECK (auth.uid() = author_id);
CREATE POLICY problems_owner_or_admin_update ON public.problems
FOR UPDATE TO authenticated
USING (auth.uid() = author_id OR public.has_role('admin'::public.app_role))
WITH CHECK (auth.uid() = author_id OR public.has_role('admin'::public.app_role));
CREATE POLICY problems_owner_or_admin_delete ON public.problems
FOR DELETE TO authenticated
USING (auth.uid() = author_id OR public.has_role('admin'::public.app_role));

CREATE POLICY answers_public_read ON public.answers
FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY answers_authenticated_insert_own ON public.answers
FOR INSERT TO authenticated WITH CHECK (auth.uid() = author_id);
CREATE POLICY answers_owner_or_admin_update ON public.answers
FOR UPDATE TO authenticated
USING (auth.uid() = author_id OR public.has_role('admin'::public.app_role))
WITH CHECK (auth.uid() = author_id OR public.has_role('admin'::public.app_role));
CREATE POLICY answers_owner_or_admin_delete ON public.answers
FOR DELETE TO authenticated
USING (auth.uid() = author_id OR public.has_role('admin'::public.app_role));

CREATE POLICY comments_public_read ON public.comments
FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY comments_authenticated_insert_own ON public.comments
FOR INSERT TO authenticated WITH CHECK (auth.uid() = author_id);
CREATE POLICY comments_owner_or_admin_update ON public.comments
FOR UPDATE TO authenticated
USING (auth.uid() = author_id OR public.has_role('admin'::public.app_role))
WITH CHECK (auth.uid() = author_id OR public.has_role('admin'::public.app_role));
CREATE POLICY comments_owner_or_admin_delete ON public.comments
FOR DELETE TO authenticated
USING (auth.uid() = author_id OR public.has_role('admin'::public.app_role));

CREATE POLICY votes_public_read ON public.votes
FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY votes_authenticated_insert_own ON public.votes
FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY votes_owner_or_admin_update ON public.votes
FOR UPDATE TO authenticated
USING (auth.uid() = user_id OR public.has_role('admin'::public.app_role))
WITH CHECK (auth.uid() = user_id OR public.has_role('admin'::public.app_role));
CREATE POLICY votes_owner_or_admin_delete ON public.votes
FOR DELETE TO authenticated
USING (auth.uid() = user_id OR public.has_role('admin'::public.app_role));

CREATE POLICY bookmarks_owner_read ON public.bookmarks
FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY bookmarks_owner_insert ON public.bookmarks
FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY bookmarks_owner_update ON public.bookmarks
FOR UPDATE TO authenticated
USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY bookmarks_owner_delete ON public.bookmarks
FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE POLICY reports_owner_or_admin_read ON public.reports
FOR SELECT TO authenticated
USING (auth.uid() = reporter_id OR public.has_role('admin'::public.app_role));
CREATE POLICY reports_authenticated_insert_own ON public.reports
FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id AND status = 'pending');
CREATE POLICY reports_admin_update ON public.reports
FOR UPDATE TO authenticated
USING (public.has_role('admin'::public.app_role))
WITH CHECK (public.has_role('admin'::public.app_role));
CREATE POLICY reports_admin_delete ON public.reports
FOR DELETE TO authenticated USING (public.has_role('admin'::public.app_role));