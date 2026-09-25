from chat_parser import parse_chat_expense

def run():
    text = "merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut"
    print("Input:", text)
    res = parse_chat_expense(text)
    print("Merchant:", res.merchant)
    print("Total Amount:", res.total_amount)
    print("Category Code:", res.category_code)
    print("Items:")
    for item in res.items:
        print(f"  * {item.quantity}x {item.name}: SAR {item.price}")

if __name__ == "__main__":
    run()
