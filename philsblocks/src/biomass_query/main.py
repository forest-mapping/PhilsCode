
from runtime4psae import run
from runtime4psae.messages import CreatedFile

import subprocess

def handler():
    subprocess.run(
        
        [
            "duckdb", 
            "<", 
            "/home/krbundy/GitHub/PhilsCode/sql/tree_1.sql"
        ]
    )
    
    return CreatedFile("./output.csv")



def main():
    return run(handler)

if __name__ == "__main__":
    main()
    