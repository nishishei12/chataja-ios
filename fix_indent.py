import re

with open("ChatAja/Features/LoginView.swift", "r") as f:
    content = f.read()

content = content.replace("                        }\n                    .padding(.horizontal, 24)", "                    }\n                    .padding(.horizontal, 24)")

with open("ChatAja/Features/LoginView.swift", "w") as f:
    f.write(content)
