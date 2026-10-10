import pytest
from unittest.mock import MagicMock
from chat_parser import check_category_active_status

def test_check_category_active_status_true_and_false():
    categories_state = {
        "active": [{"code": "OPEX-GROCERY"}, {"code": "OPEX-FUEL"}],
        "inactive": [{"code": "OPEX-DINING"}, {"code": "OPEX-PETS"}],
    }

    assert check_category_active_status("OPEX-GROCERY", categories_state) is True
    assert check_category_active_status("OPEX-FUEL", categories_state) is True
    assert check_category_active_status("OPEX-DINING", categories_state) is False
    assert check_category_active_status("OPEX-PETS", categories_state) is False
    # Unmatched fallback code defaults to active
    assert check_category_active_status("OPEX-MISC", categories_state) is True
