import os

file = __file__
file = (os.path.dirname(file)) + "/" + "../src/"
patches = os.listdir(file)

for p in patches:
    if p.endswith(".pd"):
        file_path = os.path.join(file, p)
        
        # Read all lines from the file
        with open(file_path, 'r') as f:
            lines = f.readlines()
        
        # Update the first line
        if lines:  # Check if file is not empty
            lines[0] = "#N canvas 0 0 640 480 10;\n"
        
        # Write the updated content back to the file
        with open(file_path, 'w') as f:
            f.writelines(lines)
        
        print(f"Updated: {p}")
