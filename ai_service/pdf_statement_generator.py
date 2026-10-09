"""
Monthly PDF Financial Statement Generator for Saudi Budget Tracker.
Generates an executive, branded PDF statement covering salary cycle spending,
category budgets, partner attribution split, estimated 15% VAT, and transactions.
"""

from __future__ import annotations
import io
import logging
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List

from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    HRFlowable,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

from supabase_client import get_client
from salary_cycle import get_salary_cycle_dates

logger = logging.getLogger(__name__)


def generate_monthly_pdf_statement(
    household_id: str,
    cycle_key: Optional[str] = None,
) -> bytes:
    """
    Builds a complete monthly financial statement PDF in memory and returns raw bytes.
    """
    client = get_client()

    # 1. Resolve Cycle Info
    cycle_info = get_salary_cycle_dates()
    selected_cycle_key = cycle_key or cycle_info.get("cycle_key", datetime.now(timezone.utc).strftime("%Y-%m"))
    cycle_start = cycle_info.get("cycle_start", "")
    cycle_end = cycle_info.get("cycle_end", "")
    cycle_label = cycle_info.get("cycle_label", selected_cycle_key)

    # 2. Query Budgets
    try:
        b_res = (
            client.table("budgets")
            .select("category_code, allocated_amount, spent_amount, is_active, cycle_key")
            .eq("household_id", household_id)
            .eq("is_active", True)
            .execute()
        )
        budgets_raw = b_res.data or []
    except Exception as exc:
        logger.warning("Could not fetch budgets for PDF statement: %s", exc)
        budgets_raw = []

    # Filter budgets matching cycle
    cycle_budgets = [
        b for b in budgets_raw
        if b.get("cycle_key") == selected_cycle_key or not b.get("cycle_key")
    ]

    total_allocated = sum(float(b.get("allocated_amount") or 0.0) for b in cycle_budgets)

    # 3. Query Transactions for Cycle
    try:
        t_query = (
            client.table("transactions")
            .select("id, amount, merchant, category_code, timestamp, spent_by, items")
            .eq("household_id", household_id)
            .order("timestamp", desc=True)
        )
        if cycle_start and cycle_end:
            t_query = t_query.gte("timestamp", f"{cycle_start}T00:00:00Z").lte("timestamp", f"{cycle_end}T23:59:59Z")
        
        t_res = t_query.execute()
        txs = t_res.data or []
    except Exception as exc:
        logger.warning("Could not fetch transactions for PDF statement: %s", exc)
        txs = []

    total_spent = sum(float(t.get("amount") or 0.0) for t in txs)
    total_remaining = total_allocated - total_spent
    estimated_vat = (total_spent * 0.15 / 1.15) if total_spent > 0 else 0.0

    # Partner split
    spent_me = sum(float(t.get("amount") or 0.0) for t in txs if (t.get("spent_by") or "").lower() == "me")
    spent_partner = sum(float(t.get("amount") or 0.0) for t in txs if (t.get("spent_by") or "").lower() == "partner")
    spent_both = sum(float(t.get("amount") or 0.0) for t in txs if (t.get("spent_by") or "").lower() in ("both", ""))

    # Category totals
    cat_spent: Dict[str, float] = {}
    for t in txs:
        cat = t.get("category_code") or "OPEX-MISC"
        cat_spent[cat] = cat_spent.get(cat, 0.0) + float(t.get("amount") or 0.0)

    # 4. Construct PDF Document
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=36,
        rightMargin=36,
        topMargin=36,
        bottomMargin=36,
    )

    styles = getSampleStyleSheet()

    # Custom styles
    header_style = ParagraphStyle(
        "DocHeader",
        parent=styles["Heading1"],
        fontName="Helvetica-Bold",
        fontSize=20,
        leading=24,
        textColor=colors.HexColor("#0D1117"),
    )
    subhead_style = ParagraphStyle(
        "DocSubhead",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=10,
        leading=14,
        textColor=colors.HexColor("#57606A"),
    )
    section_title = ParagraphStyle(
        "SectionTitle",
        parent=styles["Heading2"],
        fontName="Helvetica-Bold",
        fontSize=13,
        leading=16,
        textColor=colors.HexColor("#0969DA"),
        spaceBefore=10,
        spaceAfter=6,
    )
    cell_style = ParagraphStyle(
        "TableCell",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=9,
        leading=12,
        textColor=colors.HexColor("#24292F"),
    )
    cell_bold = ParagraphStyle(
        "TableCellBold",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=9,
        leading=12,
        textColor=colors.HexColor("#0D1117"),
    )

    story = []

    # Title and Branding
    story.append(Paragraph("BUDGET TRACKER — FINANCIAL STATEMENT", header_style))
    date_str = datetime.now(timezone.utc).strftime("%d %B %Y, %H:%M UTC")
    cycle_desc = f"Salary Cycle: <b>{cycle_label}</b> ({cycle_start} to {cycle_end}) &nbsp;|&nbsp; Generated: {date_str}"
    story.append(Paragraph(cycle_desc, subhead_style))
    story.append(Spacer(1, 10))
    story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor("#00C896"), spaceAfter=14))

    # Executive KPI Summary Table
    kpi_data = [
        [
            Paragraph("<b>Total Allocated</b>", cell_bold),
            Paragraph("<b>Total Spent</b>", cell_bold),
            Paragraph("<b>Remaining Balance</b>", cell_bold),
            Paragraph("<b>Est. 15% VAT</b>", cell_bold),
        ],
        [
            Paragraph(f"SAR {total_allocated:,.2f}", header_style),
            Paragraph(f"SAR {total_spent:,.2f}", ParagraphStyle("Spent", parent=header_style, textColor=colors.HexColor("#CF222E"))),
            Paragraph(
                f"SAR {total_remaining:,.2f}",
                ParagraphStyle("Rem", parent=header_style, textColor=colors.HexColor("#00C896") if total_remaining >= 0 else colors.HexColor("#CF222E")),
            ),
            Paragraph(f"SAR {estimated_vat:,.2f}", ParagraphStyle("Vat", parent=header_style, textColor=colors.HexColor("#57606A"), fontSize=16)),
        ],
    ]
    kpi_table = Table(kpi_data, colWidths=[130, 130, 130, 130])
    kpi_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F6F8FA")),
        ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#D0D7DE")),
        ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E1E4E8")),
        ("PADDING", (0, 0), (-1, -1), 8),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(kpi_table)
    story.append(Spacer(1, 14))

    # Partner Split Summary
    story.append(Paragraph("Partner Expense Allocation", section_title))
    pct_me = (spent_me / total_spent * 100) if total_spent > 0 else 0.0
    pct_partner = (spent_partner / total_spent * 100) if total_spent > 0 else 0.0
    pct_both = (spent_both / total_spent * 100) if total_spent > 0 else 0.0

    partner_data = [
        [
            Paragraph("<b>Attribution</b>", cell_bold),
            Paragraph("<b>Spent (SAR)</b>", cell_bold),
            Paragraph("<b>Share (%)</b>", cell_bold),
            Paragraph("<b>Settlement Status</b>", cell_bold),
        ],
        [
            Paragraph("👤 Spent by Me", cell_style),
            Paragraph(f"SAR {spent_me:,.2f}", cell_style),
            Paragraph(f"{pct_me:.1f}%", cell_style),
            Paragraph("Personal Spend", cell_style),
        ],
        [
            Paragraph("💜 Spent by Partner", cell_style),
            Paragraph(f"SAR {spent_partner:,.2f}", cell_style),
            Paragraph(f"{pct_partner:.1f}%", cell_style),
            Paragraph("Partner Direct Spend", cell_style),
        ],
        [
            Paragraph("👥 Shared Household (Both)", cell_style),
            Paragraph(f"SAR {spent_both:,.2f}", cell_style),
            Paragraph(f"{pct_both:.1f}%", cell_style),
            Paragraph("50 / 50 Shared Split", cell_style),
        ],
    ]
    partner_table = Table(partner_data, colWidths=[160, 120, 100, 140])
    partner_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EAEFF5")),
        ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#D0D7DE")),
        ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E1E4E8")),
        ("PADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(partner_table)
    story.append(Spacer(1, 14))

    # Category Budgets Table
    story.append(Paragraph("Category Spending Breakdown", section_title))
    cat_rows = [
        [
            Paragraph("<b>Category Code</b>", cell_bold),
            Paragraph("<b>Allocated (SAR)</b>", cell_bold),
            Paragraph("<b>Spent (SAR)</b>", cell_bold),
            Paragraph("<b>Remaining (SAR)</b>", cell_bold),
            Paragraph("<b>Usage</b>", cell_bold),
        ]
    ]

    all_cat_codes = sorted(list(set([b.get("category_code") for b in cycle_budgets] + list(cat_spent.keys()))))
    for code in all_cat_codes:
        if not code:
            continue
        alloc = next((float(b.get("allocated_amount") or 0.0) for b in cycle_budgets if b.get("category_code") == code), 0.0)
        spent = cat_spent.get(code, 0.0)
        rem = alloc - spent
        usage_pct = (spent / alloc * 100) if alloc > 0 else (100.0 if spent > 0 else 0.0)

        cat_rows.append([
            Paragraph(code, cell_bold),
            Paragraph(f"SAR {alloc:,.2f}", cell_style),
            Paragraph(f"SAR {spent:,.2f}", cell_style),
            Paragraph(
                f"SAR {rem:,.2f}",
                ParagraphStyle("CatRem", parent=cell_style, textColor=colors.HexColor("#CF222E") if rem < 0 else colors.HexColor("#1A7F37")),
            ),
            Paragraph(f"{usage_pct:.0f}%", cell_style),
        ])

    cat_table = Table(cat_rows, colWidths=[140, 95, 95, 110, 80])
    cat_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EAEFF5")),
        ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#D0D7DE")),
        ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E1E4E8")),
        ("PADDING", (0, 0), (-1, -1), 5),
    ]))
    story.append(cat_table)
    story.append(Spacer(1, 14))

    # Top Transactions Table (Up to 15)
    story.append(Paragraph(f"Transactions Recorded ({len(txs)} total, showing latest)", section_title))
    tx_rows = [
        [
            Paragraph("<b>Date</b>", cell_bold),
            Paragraph("<b>Merchant</b>", cell_bold),
            Paragraph("<b>Category</b>", cell_bold),
            Paragraph("<b>Paid By</b>", cell_bold),
            Paragraph("<b>Amount (SAR)</b>", cell_bold),
        ]
    ]
    for tx in txs[:15]:
        ts_str = str(tx.get("timestamp") or "")[:10]
        merch = str(tx.get("merchant") or "Unknown")[:22]
        cat = str(tx.get("category_code") or "OPEX-MISC")
        spent_by_val = str(tx.get("spent_by") or "both").capitalize()
        amt = float(tx.get("amount") or 0.0)

        tx_rows.append([
            Paragraph(ts_str, cell_style),
            Paragraph(merch, cell_style),
            Paragraph(cat, cell_style),
            Paragraph(spent_by_val, cell_style),
            Paragraph(f"SAR {amt:,.2f}", cell_bold),
        ])

    if len(tx_rows) == 1:
        tx_rows.append([
            Paragraph("No transactions recorded for this cycle period.", cell_style),
            Paragraph("-", cell_style),
            Paragraph("-", cell_style),
            Paragraph("-", cell_style),
            Paragraph("-", cell_style),
        ])

    tx_table = Table(tx_rows, colWidths=[80, 140, 110, 90, 100])
    tx_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EAEFF5")),
        ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#D0D7DE")),
        ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E1E4E8")),
        ("PADDING", (0, 0), (-1, -1), 5),
    ]))
    story.append(tx_table)
    story.append(Spacer(1, 16))

    # Footer Notice
    footer_text = f"Confidential Statement &bull; Generated for Household {household_id} &bull; Budget Tracker KSA"
    story.append(Paragraph(footer_text, ParagraphStyle("Footer", parent=subhead_style, alignment=1, fontSize=8)))

    # Build PDF
    doc.build(story)
    return buffer.getvalue()
