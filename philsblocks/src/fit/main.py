
from runtime4psae import run, RHandlerBridge
    
handler = RHandlerBridge(__file__)

def main():
    return run(handler)

if __name__ == "__main__":
    main()

    