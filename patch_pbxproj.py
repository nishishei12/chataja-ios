import re

with open("ChatAja.xcodeproj/project.pbxproj", "r") as f:
    text = f.read()

# Replace all occurrences of GENERATE_INFOPLIST_FILE = YES;
text = re.sub(r'(GENERATE_INFOPLIST_FILE = YES;)', r'\1\n\t\t\t\tINFOPLIST_FILE = "ChatAja/Info.plist";', text)

with open("ChatAja.xcodeproj/project.pbxproj", "w") as f:
    f.write(text)
