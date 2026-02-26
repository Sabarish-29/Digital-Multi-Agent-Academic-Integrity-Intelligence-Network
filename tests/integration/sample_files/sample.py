"""
Sample Python submission for DMAIIN integration testing.
"""


def hello_world():
    """Print a greeting message."""
    print("Hello, World!")
    return "Hello, World!"


def add(a: int, b: int) -> int:
    """Return the sum of two integers."""
    return a + b


def factorial(n: int) -> int:
    """Compute the factorial of a non-negative integer."""
    if n < 0:
        raise ValueError("Factorial is not defined for negative numbers")
    if n <= 1:
        return 1
    return n * factorial(n - 1)


if __name__ == "__main__":
    hello_world()
    print(f"2 + 3 = {add(2, 3)}")
    print(f"5! = {factorial(5)}")
