"""Tests ensuring no lazy/inline imports exist inside route handler functions."""
import ast
from pathlib import Path


def test_no_inline_imports_in_routes():
    """Verify all imports in route files are at module top-level."""
    routes_dir = Path(__file__).resolve().parent.parent / "routes"
    assert routes_dir.exists(), "Routes directory does not exist"

    route_files = list(routes_dir.glob("*.py"))
    assert len(route_files) > 0, "No route files found to inspect"

    violations = []
    for route_file in route_files:
        if route_file.name == "__init__.py":
            continue
        tree = ast.parse(route_file.read_text(encoding="utf-8"), filename=str(route_file))
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                for sub_node in ast.walk(node):
                    if isinstance(sub_node, (ast.Import, ast.ImportFrom)):
                        violations.append(
                            f"{route_file.name}:{sub_node.lineno} inside {node.name}()"
                        )

    assert not violations, f"Found inline imports inside handlers: {violations}"
