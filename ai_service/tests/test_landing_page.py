import pytest
from httpx import AsyncClient, ASGITransport
from main import app

@pytest.mark.asyncio
async def test_root_landing_page():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    html = res.text
    # Verify core branding and features
    assert "Budget Tracker" in html
    assert "ميزانية الأسرة" in html
    # Verify coming soon badges for all three app stores
    assert "Google Play" in html
    assert "App Store" in html
    assert "AppGallery" in html
    assert "قريباً" in html
    # Verify developer email
    assert "abedmowafaq@gmail.com" in html
    # Verify feature descriptions
    assert "دورة الراتب" in html  # Flexible salary cycle
    assert "الذكاء الاصطناعي" in html  # AI
    assert "الادخار" in html  # Savings reserve

@pytest.mark.asyncio
async def test_auth_confirm_landing():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/auth/confirm")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]
    html = res.text
    assert "تم تأكيد البريد الإلكتروني بنجاح" in html
    assert "budgettracker://login" in html
    assert "abedmowafaq@gmail.com" in html

@pytest.mark.asyncio
async def test_auth_callback_landing():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res = await ac.get("/auth/callback")
    assert res.status_code == 200
    assert "text/html" in res.headers["content-type"]

@pytest.mark.asyncio
async def test_hero_background_images():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        res_webp = await ac.get("/hero-bg.webp")
        res_jpg = await ac.get("/hero-bg.jpg")
    assert res_webp.status_code == 200
    assert "image/webp" in res_webp.headers["content-type"]
    assert res_jpg.status_code == 200
    assert "image/jpeg" in res_jpg.headers["content-type"]

