# Dependents & Hybrid Subcategories Design Specification

## Overview
This feature introduces a two-dimensional attribution model for household transactions (Who Paid vs. For Whom) with deep support for children/dependents, alongside a hybrid (transaction-level and item-level) subcategory architecture driven by LLM reasoning and interactive user confirmation.

## Problem Statement
1. **Missing Subcategories in AI Chat & Transaction Management:**
   - In the AI chat preview card, users cannot review or change the subcategory before saving.
   - Transactions default to general/null subcategories (e.g. 25 SAR broasted meal at Al Baik defaults to "Other" instead of `restaurants_dinners`).
   - In the transaction edit sheet, only the main category dropdown is present; subcategories cannot be viewed or reassigned.
   - The Flutter Dart model `Transaction` omitted `subCategory`.
2. **Missing Attribution Flexibility & Dependents:**
   - Transactions only support binary partners (`me` and `partner`) and a single legacy `spent_by` field in the chat preview card.
   - Real households have children, whose expenses are shared family costs, but parents cannot attribute expenses to specific children (e.g., "Sarah" vs. "Fahad") for budgeting and analytics.
   - The AI chat preview card lacked the "For Whom" selector, only offering a 1D "Spent By" choice.
3. **AI Chat Parser Vocabulary Limitations:**
   - The LLM prompt used a static category list without subcategories or household dependents.
   - Python keyword matching failed on Arabic plurals (e.g., `المطاعم` vs `مطعم`) and lacked common Saudi dining terminology (e.g., `شاورما`, `بروستد`, `بخاري`).

---

## Architectural Design

### 1. Database & Migrations
- **Table: `household_dependents`**
  ```sql
  CREATE TABLE IF NOT EXISTS public.household_dependents (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      avatar_icon TEXT DEFAULT 'child',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX IF NOT EXISTS idx_dependents_household ON public.household_dependents(household_id);
  ```
  - Enabled RLS for household authenticated members (SELECT, INSERT, UPDATE, DELETE).
- **Sub-Categories Keyword Seed Expansion:**
  - Update `cost_control_sub_categories` keywords to include Saudi culinary terms and plural forms (`مطاعم`, `شاورما`, `بروستد`, `وجبة`, `سندويش`, `مشويات`, `فطور`, `كبسة`, `بخاري`, `برجر`, `كافيه`, `مخبز`, `حلا`, `كيك`, `كرواسون`, `شاهي`, `دونات`, `لاتيه`, `سبانش`).
- **Transaction Model Verification:**
  - Ensure `transactions.sub_category` is properly indexed and referenced.

### 2. Backend & AI Service (`ai_service`)
- **Household Dependents Management API:**
  - `GET /households/{household_id}/dependents` -> returns list of dependents.
  - `POST /households/{household_id}/dependents` -> creates a dependent for the household.
  - `DELETE /households/{household_id}/dependents/{dependent_id}` -> removes a dependent.
- **Dynamic Taxonomy & Dependents AI Prompting:**
  - `chat_parser.py`: In `handle_chat_expense`, dynamically fetch:
    1. Active household categories and their associated sub-categories.
    2. Household registered dependents list.
  - Prompt LiteLLM with active taxonomy and dependents list.
  - Structured output schema:
    ```json
    {
      "merchant": "...",
      "total_amount": 0.0,
      "category_code": "...",
      "sub_category": "...",
      "paid_by": "me" | "partner",
      "beneficiary": "me" | "partner" | "both" | "<dependent_name>",
      "items": [
        {"name": "...", "quantity": 1, "price": 0.0, "sub_category": "..."}
      ]
    }
    ```
- **Interactive Preview Card Payload:**
  - Return `category_code`, `sub_category`, `available_categories`, `available_sub_categories`, `paid_by`, `beneficiary`, `items` (with item-level `sub_category`), and `dependents` in `pending_confirmation`.
- **Fair-Share Settlement Engine:**
  - In `settlement_engine.py`, any transaction where `beneficiary` matches a dependent (or starts with `child:`) is treated as a **shared family expense** (same as `both`), splitting based on the household's `split_ratio`.

### 3. Mobile Frontend (`flutter_app`)
- **Data Model:**
  - Add `final String? subCategory;` to `Transaction` model in `models.dart`.
  - Create `HouseholdDependent` model (`id`, `householdId`, `name`, `avatarIcon`, `createdAt`).
- **Household Settings:**
  - Extend `HouseholdManagementCard` with a "Family Dependents & Children" section allowing adding, viewing, and deleting children chips.
- **Enhanced Chat Preview Confirmation Card:**
  - `PendingExpenseConfirmationCard`:
    - Store name input.
    - Category & Sub-category dropdowns (dynamically cascading).
    - "WHO PAID?" segment (`Me` / `Partner`).
    - "FOR WHOM?" segment (`Me` / `Partner` / `Both` / Child chips).
    - Item breakdown displaying item name, price, and sub-category chip.
- **Edit Transaction Sheet:**
  - `EditTransactionSheet`:
    - Add cascading Sub-category dropdown.
    - Add Child chips to "FOR WHOM?".
    - Save updated `sub_category`, `paid_by`, and `beneficiary`.
