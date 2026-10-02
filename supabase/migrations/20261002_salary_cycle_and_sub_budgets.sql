-- Migration: 20261002_salary_cycle_and_sub_budgets.sql
-- Description: Adds cycle_key, previous_cycle_delta, and is_active to budgets;
--              adds sub_category and cycle_key to transactions;
--              creates and seeds cost_control_sub_categories.

-- 1. Budgets table updates
ALTER TABLE budgets 
  ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7),
  ADD COLUMN IF NOT EXISTS previous_cycle_delta NUMERIC(12, 2) DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_budgets_household_cycle ON budgets(household_id, cycle_key);

-- 2. Transactions table updates
ALTER TABLE transactions 
  ADD COLUMN IF NOT EXISTS sub_category VARCHAR(50),
  ADD COLUMN IF NOT EXISTS cycle_key VARCHAR(7);

CREATE INDEX IF NOT EXISTS idx_transactions_cycle ON transactions(household_id, cycle_key);

-- 3. Sub-categories table
CREATE TABLE IF NOT EXISTS cost_control_sub_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_code VARCHAR(50) NOT NULL REFERENCES cost_control_codes(code) ON DELETE CASCADE,
  sub_code VARCHAR(50) NOT NULL,
  name_en VARCHAR(100) NOT NULL,
  name_ar VARCHAR(100) NOT NULL,
  keywords TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT uq_parent_sub UNIQUE (parent_code, sub_code)
);

-- 4. Seed Sub-Categories
INSERT INTO cost_control_sub_categories (parent_code, sub_code, name_en, name_ar, keywords) VALUES
('OPEX-GROCERY', 'meat', 'Meat & Poultry', 'اللحوم والدواجن', ARRAY['meat', 'chicken', 'beef', 'lamb', 'لحم', 'دجاج']),
('OPEX-GROCERY', 'vegetables_fruit', 'Fresh Produce & Fruits', 'الخضار والفواكه', ARRAY['produce', 'vegetables', 'fruit', 'خضار', 'فواكه']),
('OPEX-GROCERY', 'dairy_eggs', 'Dairy & Eggs', 'الألبان والبيض', ARRAY['milk', 'cheese', 'yogurt', 'eggs', 'حليب', 'جبن', 'بيض']),
('OPEX-GROCERY', 'snacks_chips', 'Snacks, Chips & Sweets', 'الشيبس والسناكات والحلويات', ARRAY['chips', 'snack', 'chocolate', 'candy', 'شيبس', 'بسكويت']),
('OPEX-GROCERY', 'beverages', 'Beverages & Water', 'المشروبات والمياه', ARRAY['water', 'juice', 'soda', 'pepsi', 'ماء', 'عصير']),
('OPEX-GROCERY', 'pantry_staples', 'Pantry & Staples', 'التموين والمؤن', ARRAY['rice', 'oil', 'flour', 'sugar', 'أرز', 'زيت', 'سكر']),
('OPEX-GROCERY', 'cleaning_household', 'Cleaning & Household Supplies', 'المنظفات ومستلزمات المنزل', ARRAY['soap', 'detergent', 'tissue', 'صابون', 'مناديل']),

('OPEX-UTILITIES', 'housing_rent', 'Housing Rent', 'إيجار السكن', ARRAY['rent', 'apartment', 'housing', 'إيجار']),
('OPEX-UTILITIES', 'electricity_sec', 'Electricity (SEC)', 'فاتورة الكهرباء', ARRAY['electricity', 'sec', 'كهرباء']),
('OPEX-UTILITIES', 'fiber_internet', 'Home Fiber Internet', 'الإنترنت المنزلي', ARRAY['internet', 'fiber', 'stc fiber', 'mobily fiber', 'إنترنت']),
('OPEX-UTILITIES', 'mobile_sims', 'Mobile SIMs & Data', 'باقات الجوال والاتصالات', ARRAY['sim', 'prepaid', 'postpaid', 'stc', 'mobily', 'zain', 'شحن']),
('OPEX-UTILITIES', 'water_municipal', 'Water & Municipal Bills', 'المياه والخدمات البلدية', ARRAY['water', 'nwc', 'مياه']),

('OPEX-DINING', 'restaurants_dinners', 'Restaurants & Meals', 'المطاعم والوجبات', ARRAY['restaurant', 'dinner', 'lunch', 'burger', 'مطعم']),
('OPEX-DINING', 'coffee_bakeries', 'Coffee & Bakeries', 'القهوة والمخابز', ARRAY['coffee', 'cafe', 'starbucks', 'dunkin', 'قهوة', 'كافيه']),
('OPEX-DINING', 'delivery_apps', 'Delivery Apps', 'تطبيقات التوصيل', ARRAY['hungerstation', 'jahez', 'toyou', 'هنقرستيشن', 'جاهز']),

('OPEX-FUEL', 'gas_fuel', 'Gasoline & Fuel', 'بنزين ووقود', ARRAY['gas', 'fuel', 'petrol', 'aramco', 'بنزين', 'وقود']),
('OPEX-FUEL', 'car_maintenance', 'Car Maintenance & Oil', 'صيانة وتغيير الزيت', ARRAY['oil change', 'mechanic', 'tires', 'صيانة', 'زيت']),
('OPEX-FUEL', 'ride_hailing', 'Ride Hailing (Uber/Bolt)', 'تطبيقات النقل والتوصيل', ARRAY['uber', 'bolt', 'careem', 'أوبر', 'بوليت']),

('OPEX-HEALTH', 'prescriptions_meds', 'Prescriptions & Medicines', 'الأدوية والوصفات', ARRAY['pharmacy', 'medicine', 'dawaa', 'nahdi', 'صيدلية', 'دواء']),
('OPEX-HEALTH', 'clinics_dental', 'Clinics & Dental', 'العيادات والأسنان', ARRAY['clinic', 'dental', 'doctor', 'hospital', 'عيادة', 'أسنان']),

('OPEX-SHOPPING', 'clothing_fashion', 'Clothing & Fashion', 'الملابس والأزياء', ARRAY['clothes', 'fashion', 'zara', 'h&m', 'ملابس']),
('OPEX-SHOPPING', 'electronics_gadgets', 'Electronics & Gadgets', 'الإلكترونيات والتقنية', ARRAY['jarir', 'extra', 'apple', 'electronics', 'إلكترونيات']),
('OPEX-SHOPPING', 'home_furniture', 'Home Goods & Furniture', 'الأثاث والمفروشات', ARRAY['ikea', 'furniture', 'home', 'أثاث'])
ON CONFLICT (parent_code, sub_code) DO NOTHING;

-- 5. Backfill cycle_key for existing budgets
UPDATE budgets SET cycle_key = '2026-10' WHERE (month = '2026-10-01' OR cycle_key IS NULL) AND cycle_key IS NULL;
UPDATE budgets SET cycle_key = '2026-09' WHERE month = '2026-09-01' AND cycle_key IS NULL;

