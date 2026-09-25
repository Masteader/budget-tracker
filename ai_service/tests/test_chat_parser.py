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
    assert len(result.items) == 2
    assert result.items[0].name == "Ice Latte"
    assert result.items[1].price == 3.0
