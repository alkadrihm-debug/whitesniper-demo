import sys


def greet(name):
    return f"hello {name}"


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "world"
    print(greet(name))
