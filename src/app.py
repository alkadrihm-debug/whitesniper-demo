import subprocess
import sys

def run_command(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True)
    return result.stdout.decode()

if __name__ == "__main__":
    user_input = sys.argv[1] if len(sys.argv) > 1 else "echo 'hello'"
    output = run_command(user_input)
    print(output)
