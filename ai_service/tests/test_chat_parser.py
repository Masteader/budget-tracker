"""
Unit tests for natural language chat transaction parser.
"""
from unittest.mock import patch, MagicMock
from chat_parser import parse_chat_expense, ParsedChatExpense, ChatLineItem

def test_parsed_chat_expense_model():
    item1 = ChatLineItem(name="Ice Latte", quantity=1.0, price=16.0)
    item2 = ChatLineItem(name="Donut", quantity=1.0, price=3.0)
    expense = ParsedChatExpense(
        merchant="Dunkin'",
        total_amount=19.0,
        currency="SAR",
        category_code="OPEX-DINING",
        items=[item1, item2],
    )
    assert expense.merchant == "Dunkin'"
    assert expense.total_amount == 19.0
    assert len(expense.items) == 2
    assert expense.items[0].price == 16.0
    assert expense.items[1].name == "Donut"

@patch("chat_parser.litellm.completion")
def test_parse_chat_expense_mocked(mock_completion):
    mock_resp = MagicMock()
    mock_resp.choices = [
        MagicMock(
            message=MagicMock(
                content='''{
                    "is_transaction": true,
                    "merchant": "Dunkin",
                    "total_amount": 19.0,
                    "currency": "SAR",
                    "category_code": "OPEX-DINING",
                    "items": [
                        {"name": "Ice Latte", "quantity": 1, "price": 16.0},
                        {"name": "Donut", "quantity": 1, "price": 3.0}
                    ]
                }'''
            )
        )
    ]
    mock_completion.return_value = mock_resp

    result = parse_chat_expense("merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut")
    assert result.merchant == "Dunkin"
    assert result.total_amount == 19.0
    assert result.category_code == "OPEX-DINING"
    assert result.spent_by == "both"  # default fallback if omitted from mocked JSON
    assert len(result.items) == 2
    assert result.items[0].name == "Ice Latte"
    assert result.items[1].price == 3.0

def test_normalize_arabic_numbers():
    from chat_parser import normalize_arabic_numbers
    assert normalize_arabic_numbers("عبيت بـ ٥٠ ريال بنزين ٩١") == "عبيت بـ 50 ريال بنزين 91"
    assert normalize_arabic_numbers("فاتورة ١٢٣.٤٥ ريال") == "فاتورة 123.45 ريال"

def test_saudi_dialect_heuristic_parsing():
    from chat_parser import _fallback_heuristic_parse
    # 1. Fuel with Sasco
    res_fuel = _fallback_heuristic_parse("عبيت بنزين 91 بـ 60 ريال من ساسكو")
    assert res_fuel.merchant == "SASCO"
    assert res_fuel.total_amount == 60.0
    assert res_fuel.category_code == "OPEX-FUEL"
    assert res_fuel.spent_by == "me"

    # 2. Grocery with Panda and Eastern numerals
    res_groc = _fallback_heuristic_parse("تقضينا من بنده مقاضي البيت بـ ٨٥ ريال")
    assert res_groc.merchant == "Panda"
    assert res_groc.total_amount == 85.0
    assert res_groc.category_code == "OPEX-GROCERY"
    assert res_groc.spent_by == "both"

    # 3. Dining with Albaik
    res_dining = _fallback_heuristic_parse("طلبنا من البيك بـ 54 ريال دفعتها انا")
    assert res_dining.merchant == "Albaik"
    assert res_dining.total_amount == 54.0
    assert res_dining.category_code == "OPEX-DINING"
    assert res_dining.spent_by == "me"
