-- Allow authenticated and anon users to read cost_control_sub_categories catalog
ALTER TABLE IF EXISTS cost_control_sub_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cost_control_sub_categories_select_all" ON cost_control_sub_categories;
CREATE POLICY "cost_control_sub_categories_select_all"
    ON cost_control_sub_categories FOR SELECT
    TO authenticated, anon
    USING (true);
